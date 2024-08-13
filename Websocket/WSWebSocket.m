//
//  WSWebSocket.m
//  WSWebSocket
//
//  Created by Andras Koczka on 2/7/12.
//  Copyright (c) 2012 Andras Koczka
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is furnished
//  to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included
//  in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//  FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//  COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//  IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
//  WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "WSWebSocket.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

#import "NSString+Base64.h"
#import "WSFrame.h"
#import "WSMessage.h"
#import "WSMessageProcessor.h"

#define WSSafeCFRelease(obj) if (obj) CFRelease(obj)


static const NSUInteger WSNonceSize = 16;
static const NSUInteger WSPort = 80;
static const NSUInteger WSPortSecure = 443;
static NSString *const WSAcceptGUID = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
static NSString *const WSScheme = @"ws";
static NSString *const WSSchemeSecure = @"wss";

static CFStringRef const kWSConnection = CFSTR("Connection");
static CFStringRef const kWSConnectionValue = CFSTR("Upgrade");
static CFStringRef const kWSGet = CFSTR("GET");
static CFStringRef const kWSHost = CFSTR("Host");
static CFStringRef const kWSHTTP11 = CFSTR("HTTP/1.1");
static CFStringRef const kWSOrigin = CFSTR("Origin");
static CFStringRef const kWSUpgrade = CFSTR("Upgrade");
static CFStringRef const kWSUpgradeValue = CFSTR("websocket");
static CFStringRef const kWSVersion = CFSTR("13");
static CFStringRef const kWSContentLength = CFSTR("Content-Length");

static CFStringRef const kWSSecWebSocketAccept = CFSTR("Sec-WebSocket-Accept");
static CFStringRef const kWSSecWebSocketExtensions = CFSTR("Sec-WebSocket-Extensions");
static CFStringRef const kWSSecWebSocketKey = CFSTR("Sec-WebSocket-Key");
static CFStringRef const kWSSecWebSocketProtocol = CFSTR("Sec-WebSocket-Protocol");
static CFStringRef const kWSSecWebSocketVersion = CFSTR("Sec-WebSocket-Version");

static const NSUInteger WSHTTPCode101 = 101;


typedef enum {
    WSWebSocketStateNone = 0,
    WSWebSocketStateConnecting = 1,
    WSWebSocketStateOpen = 2,
    WSWebSocketStateClosing = 3,
    WSWebSocketStateClosed = 4
}WSWebSocketStateType;


@implementation WSWebSocket {
    NSArray *protocols;
    
    NSInputStream *inputStream;
    NSOutputStream *outputStream;
    BOOL hasSpaceAvailable;
    
    NSMutableData *dataReceived;
    NSData *dataToSend;
    NSInteger bytesSent;

    WSWebSocketStateType state;
    NSString *acceptKey;

    NSThread *wsThread;
    dispatch_queue_t callbackQueue;
    void (^dataCallback)(NSData *data);
    void (^textCallback)(NSString *text);
    void (^pongCallback)(void);
    void (^closeCallback)(NSUInteger statusCode, NSString *message);
    void (^responseCallback)(NSHTTPURLResponse *response, NSData *data);

    WSMessageProcessor *messageProcessor;    
    WSFrame *currentFrame;
    uint16_t statusCode;
    NSString *closingReason;
}


@synthesize fragmentSize;
@synthesize hostURL;
@synthesize selectedProtocol;


- (void)setFragmentSize:(NSUInteger)aFragmentSize {
    fragmentSize = aFragmentSize;
    
    if (fragmentSize < 131) {
        fragmentSize = 131;
    }

    messageProcessor.fragmentSize = fragmentSize;
}


#pragma mark - Object lifecycle


- (id)initWithURL:(NSURL *)url protocols:(NSArray *)protocolStrings {
    self = [super init];
    if (self) {
        [self analyzeURL:url];
        hostURL = url;
        protocols = protocolStrings;
        messageProcessor = [[WSMessageProcessor alloc] init];
        self.fragmentSize = NSUIntegerMax;
        callbackQueue = dispatch_queue_create("WebSocket callback queue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    //dispatch_release(callbackQueue);
    callbackQueue = nil;
}


#pragma mark - Callbacks


- (void)setDataCallback:(void (^)(NSData *data))aDataCallback {
    dataCallback = aDataCallback;
}

- (void)setTextCallback:(void (^)(NSString *text))aTextCallback {
    textCallback = aTextCallback;
}

- (void)setPongCallback:(void (^)(void))aPongCallback {
    pongCallback = aPongCallback;
}

- (void)setCloseCallback:(void (^)(NSUInteger statusCode, NSString *message))aCloseCallback {
    closeCallback = aCloseCallback;
}

- (void)setResponseCallback:(void (^)(NSHTTPURLResponse *response, NSData *data))aResponseCallback {
    responseCallback = aResponseCallback;
}


#pragma mark - Helper methods


- (void)analyzeURL:(NSURL *)url {
    NSAssert(url.scheme, @"Incorrect URL. Unable to determine scheme from URL: %@", url);
    NSAssert(url.host, @"Incorrect URL. Unable to determine host from URL: %@", url);
}

- (NSData *)SHA1DigestOfString:(NSString *)aString {
    NSData *data = [aString dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, data.length, digest);
    
    return [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
}

- (NSString *)nonce {
    uint8_t nonce[WSNonceSize];
    SecRandomCopyBytes(kSecRandomDefault, WSNonceSize, nonce);
    return [NSString encodeBase64WithData:[NSData dataWithBytes:nonce length:WSNonceSize]];
}

- (NSString *)acceptKeyFromNonce:(NSString *)nonce {
    return [NSString encodeBase64WithData:[self SHA1DigestOfString:[nonce stringByAppendingString:WSAcceptGUID]]];    
}


#pragma mark - Data stream


- (void)initiateConnection {
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    NSUInteger port = (hostURL.port) ? hostURL.port.integerValue : ([hostURL.scheme.lowercaseString isEqualToString:WSScheme.lowercaseString]) ? WSPort : WSPortSecure;
    
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)hostURL.host, port, &readStream, &writeStream);

    inputStream = (__bridge_transfer NSInputStream *)readStream;
    outputStream = (__bridge_transfer NSOutputStream *)writeStream;

    if ([hostURL.scheme isEqualToString:WSSchemeSecure]) {
        [inputStream setProperty:NSStreamSocketSecurityLevelTLSv1 forKey:NSStreamSocketSecurityLevelKey];
        [outputStream setProperty:NSStreamSocketSecurityLevelTLSv1 forKey:NSStreamSocketSecurityLevelKey];
    }

    inputStream.delegate = self;
    outputStream.delegate = self;
    [inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];    
    [inputStream open];
    [outputStream open];
}

- (void)closeConnection {
    [inputStream close];
    [outputStream close];
    [inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    inputStream.delegate = nil;
    outputStream.delegate = nil;
    inputStream = nil;
    outputStream = nil;
    state = WSWebSocketStateClosed;

    if (closeCallback) {
        dispatch_async(callbackQueue, ^{
            closeCallback(statusCode, closingReason);
        });
    }
}


#pragma mark - Receive data


- (BOOL)constructMessage {

    if (!dataReceived.length) {
        return NO;
    }
    
    NSUInteger bytesConstructed = messageProcessor.bytesConstructed;
    WSMessage *message = [messageProcessor constructMessageFromData:dataReceived];
        
    // Close frame
    if (message.opcode == WSWebSocketOpcodeClose) {
        [self sendCloseControlFrameWithStatusCode:message.statusCode text:message.text];
    }
    
    // Ping frame
    if (message.opcode == WSWebSocketOpcodePing) {
        WSFrame *frame = [[WSFrame alloc] initWithOpcode:WSWebSocketOpcodePong data:message.data maxSize:fragmentSize];
        [messageProcessor queueFrame:frame];
        [self sendData];
    }
    
    // Pong frame
    if (message.opcode == WSWebSocketOpcodePong && pongCallback) {
        dispatch_async(callbackQueue, ^{
            pongCallback();
        });
    }
    
    // Text message
    if (message.opcode == WSWebSocketOpcodeText && textCallback) {
        
        // Execute the callback block with the constructed message.
        dispatch_async(callbackQueue, ^{
            textCallback(message.text);
        });
    }
    
    // Binary message
    else if (message.opcode == WSWebSocketOpcodeBinary && dataCallback) {

        // Execute the callback block with the constructed message.
        dispatch_async(callbackQueue, ^{
            dataCallback(message.data);
        });
    }

    return bytesConstructed != messageProcessor.bytesConstructed;
}

- (void)readFromStream {
    
    if(!dataReceived) {
        dataReceived = [[NSMutableData alloc] init];
    }
    
    NSUInteger bufferSize = fragmentSize;
    
    // Use a reasonable buffer size
    if (fragmentSize == NSUIntegerMax) {
        bufferSize = 4096;
    }
    
    uint8_t buffer[bufferSize];
    
    // Read from the stream
    NSInteger length = [inputStream read:buffer maxLength:bufferSize];

    // Append the bytes read from the stream
    if (length > 0) {
        [dataReceived appendBytes:(const void *)buffer length:length];
    }
    else {
        return;
    }

    if (state == WSWebSocketStateConnecting) {
        [self processResponse];
    }    

    if (state == WSWebSocketStateOpen || state == WSWebSocketStateClosing) {
        
        // Process all the received data or until a partial received fragment is found
        while (messageProcessor.bytesConstructed != dataReceived.length && [self constructMessage]) {
        }
        
        // All data processed
        if (messageProcessor.bytesConstructed == dataReceived.length) {
            dataReceived = nil;
            messageProcessor.bytesConstructed = 0;
        }
    }
}


#pragma mark - Send data


- (void)sendCloseControlFrameWithStatusCode:(uint16_t)code text:(NSString *)text {
    
    if (state != WSWebSocketStateOpen) {
        return;
    }
    
    state = WSWebSocketStateClosing;
    
    NSData *messageData = [text dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t length = (code) ? 2 + messageData.length : 0;
    
    NSData *frameData;
    
    // Create the data from the status code and the message
    if (length) {
        
        // Invalid status code
        if (code != 1000 && code != 1001 && code != 1002 && code != 1003 && code != 1007 && code != 1008 && code != 1009 && code != 1010 && code != 1011 && code < 3000) {
            code = 1002;
        }
        
        uint8_t buffer[length];
        uint8_t *payloadData = (uint8_t *)buffer;
        uint16_t *code16 = (uint16_t *)payloadData;
        *code16 = CFSwapInt16HostToBig(code);
        
        statusCode = code;
        
        if (messageData.length) {
            payloadData += 2;
            (void)memcpy(payloadData, messageData.bytes, messageData.length);
            closingReason = text;
        }
        
        frameData = [NSData dataWithBytes:buffer length:length];
    }

    WSFrame *frame = [[WSFrame alloc] initWithOpcode:WSWebSocketOpcodeClose data:frameData maxSize:fragmentSize];
    [messageProcessor queueFrame:frame];
    [self sendData];
}

- (void)sendData {
    if (!hasSpaceAvailable) {
        return;
    }

    if (state == WSWebSocketStateOpen || state == WSWebSocketStateClosing) {

        if (state == WSWebSocketStateOpen) {
            [messageProcessor scheduleNextMessage];
        }
        
        [messageProcessor processMessage];

        if (!dataToSend) {
            currentFrame = [messageProcessor nextFrame];
            dataToSend = currentFrame.data;
        }
    }
    
    [self writeToStream];    
}

- (void)writeToStream {
    if (!dataToSend) {
        return;
    }
    
    uint8_t *dataBytes = (uint8_t *)[dataToSend bytes];
    dataBytes += bytesSent;
    uint64_t length = dataToSend.length - bytesSent;
    
    hasSpaceAvailable = NO;
    length = [outputStream write:dataBytes maxLength:length];
    
    if (length > 0) {
        bytesSent += length;

        // All data has been sent
        if (bytesSent == dataToSend.length) {
            bytesSent = 0;
            dataToSend = nil;
            currentFrame = nil;
        }
    }
}


#pragma mark - NSStreamDelegate


- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            break;
        case NSStreamEventHasBytesAvailable:            
            if (aStream == inputStream) {
                [self readFromStream];
            }
            break;
        case NSStreamEventHasSpaceAvailable:            
            if (aStream == outputStream) {
                hasSpaceAvailable = YES;
                [self sendData];
            }
            break;
        case NSStreamEventErrorOccurred:
            statusCode = aStream.streamError.code;
            closingReason = [NSString stringWithFormat:@"%@ - %@", aStream.streamError.domain, aStream.streamError.localizedDescription];
            [self closeConnection];
            break;
        case NSStreamEventEndEncountered:
            [self closeConnection];
            break;
        default:
            //NSLog(@"Unknown event");
            break;
    }
}


#pragma mark - Handshake


- (void)sendOpeningHandshakeWithRequest:(NSURLRequest *)request {
    NSString *nonce = [self nonce];
    NSString *hostPort = (hostURL.port) ? [NSString stringWithFormat:@"%@:%@", hostURL.host, hostURL.port] : hostURL.host;
    
    CFHTTPMessageRef message;

    if (request) {
        message = CFHTTPMessageCreateRequest(kCFAllocatorDefault, (__bridge CFStringRef)request.HTTPMethod, (__bridge CFURLRef)request.URL, kWSHTTP11);
        
        // Copy header fields from request
        for (NSString *headerField in request.allHTTPHeaderFields) {
            CFHTTPMessageSetHeaderFieldValue(message, (__bridge CFStringRef)headerField, (__bridge CFStringRef)[request.allHTTPHeaderFields objectForKey:headerField]);
        }
        
        // Copy body
        if (request.HTTPBody) {
            CFHTTPMessageSetBody(message, (__bridge CFDataRef)request.HTTPBody);
        }
        
    }
    else {
        message = CFHTTPMessageCreateRequest(kCFAllocatorDefault, kWSGet, (__bridge CFURLRef)hostURL, kWSHTTP11);
    }

    NSAssert(message, @"Message could not be created from url: %@", hostURL);
    
    CFHTTPMessageSetHeaderFieldValue(message, kWSHost, (__bridge CFStringRef)hostPort);
    CFHTTPMessageSetHeaderFieldValue(message, kWSUpgrade, kWSUpgradeValue);
    CFHTTPMessageSetHeaderFieldValue(message, kWSConnection, kWSConnectionValue);
    CFHTTPMessageSetHeaderFieldValue(message, kWSSecWebSocketVersion, kWSVersion);
    CFHTTPMessageSetHeaderFieldValue(message, kWSSecWebSocketKey, (__bridge CFStringRef)nonce);

    NSMutableString *protocolList;

    // Create a protocol list from the protocol strings
    for (NSString *protocolString in protocols) {
        if (!protocolList) {
            protocolList = [[NSMutableString alloc] initWithString:protocolString];
        }
        else {
            [protocolList appendFormat:@",%@", protocolString];
        }
    }
    
    // Set the web socket protocol field
    if (protocolList.length) {
        CFHTTPMessageSetHeaderFieldValue(message, kWSSecWebSocketProtocol, (__bridge CFStringRef)protocolList);
    }
    
    CFDataRef messageData = CFHTTPMessageCopySerializedMessage(message);
    dataToSend = (__bridge_transfer NSData *)messageData;
    acceptKey = [self acceptKeyFromNonce:nonce];
    
    CFRelease(message);
    
//    //NSLog(@"%@", [[NSString alloc] initWithData:dataToSend encoding:NSUTF8StringEncoding]);
}

- (BOOL)isValidHandshake:(CFHTTPMessageRef)response {
    BOOL isValid = YES;
    
    uint32_t responseStatusCode = CFHTTPMessageGetResponseStatusCode(response);
    
    if (responseStatusCode != WSHTTPCode101) {
        isValid = NO;
    }

    CFStringRef upgradeValue = CFHTTPMessageCopyHeaderFieldValue(response, kWSUpgrade);
    CFStringRef connectionValue = CFHTTPMessageCopyHeaderFieldValue(response, kWSConnection);
    CFStringRef acceptValue = CFHTTPMessageCopyHeaderFieldValue(response, kWSSecWebSocketAccept);
    CFStringRef protocolValue = CFHTTPMessageCopyHeaderFieldValue(response, kWSSecWebSocketProtocol);
    
    if (!upgradeValue || CFStringCompare(upgradeValue, kWSUpgradeValue, kCFCompareCaseInsensitive) != kCFCompareEqualTo) {
        isValid = NO;
    }

    if (!connectionValue || CFStringCompare(connectionValue, kWSConnectionValue, kCFCompareCaseInsensitive) != kCFCompareEqualTo) {
        isValid = NO;
    }

    if (!acceptValue || CFStringCompare(acceptValue, (__bridge CFStringRef)acceptKey, kCFCompareCaseInsensitive) != kCFCompareEqualTo) {
        isValid = NO;
    }

    if (protocolValue) {
        selectedProtocol = (__bridge_transfer NSString *)protocolValue;

        // Selected protocol is not in the protocol list - it should fail the connection
        if ([protocols indexOfObject:selectedProtocol] == NSNotFound) {
            isValid = NO;
            [self closeConnection];
        }
    }
    
    WSSafeCFRelease(upgradeValue);
    WSSafeCFRelease(connectionValue);
    WSSafeCFRelease(acceptValue);

//    CFDataRef messageData = CFHTTPMessageCopySerializedMessage(response);
//    //NSLog(@"%@", [[NSString alloc] initWithData:(__bridge_transfer NSData*)messageData encoding:NSUTF8StringEncoding]);

    return isValid;
}

- (void)analyzeResponse:(CFHTTPMessageRef)response {
    
    if ([self isValidHandshake:response]) {
        state = WSWebSocketStateOpen;
        [self sendData];
    }

    if (responseCallback) {

        uint32_t responseStatusCode = CFHTTPMessageGetResponseStatusCode(response);
        NSDictionary *headerFields = (__bridge_transfer NSDictionary *)CFHTTPMessageCopyAllHeaderFields(response);
        NSHTTPURLResponse *HTTPURLResponse = [[NSHTTPURLResponse alloc] initWithURL:hostURL statusCode:responseStatusCode HTTPVersion:(__bridge NSString *)kWSHTTP11 headerFields:headerFields];
        NSData *data = (__bridge_transfer NSData *)CFHTTPMessageCopyBody(response);

        dispatch_async(callbackQueue, ^{
            responseCallback(HTTPURLResponse, data);
        });
    }
    else if (state == WSWebSocketStateConnecting) {
        [self closeConnection];
    }
}

- (void)processResponse {
    uint8_t *dataBytes = (uint8_t *)[dataReceived bytes];
    
    // Find end of the header
    for (int i = 0; i < dataReceived.length - 3; i++) {
        
        // If we have complete header
        if (dataBytes[i] == 0x0d && dataBytes[i + 1] == 0x0a && dataBytes[i + 2] == 0x0d && dataBytes[i + 3] == 0x0a) {
            
            NSUInteger responseLength = i + 4;
            BOOL isResponseComplete = YES;
            
            // Create a CFMessage from the response
            CFHTTPMessageRef response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, NO);
            CFHTTPMessageAppendBytes(response, dataBytes, responseLength);
            
            // Check if it has a body
            CFStringRef contentLengthString = CFHTTPMessageCopyHeaderFieldValue(response, kWSContentLength);
            
            if (contentLengthString) {
                
                NSUInteger contentLength = CFStringGetIntValue(contentLengthString);
                responseLength += contentLength;
                
                // Not enough data received - body is not complete
                if (dataReceived.length < responseLength) {
                    isResponseComplete = NO;
                }
                else {
                    // Add the body data to the response
                    uint8_t *contentBytes = (uint8_t *)(dataBytes + i + 4);
                    CFHTTPMessageAppendBytes(response, contentBytes, contentLength);
                }
                
                CFRelease(contentLengthString);
            }
            
            if (isResponseComplete) {
                
                // Analize it
                [self analyzeResponse:response];
                
                // Remove the processed handshake data
                if (dataReceived.length == responseLength) {
                    dataReceived = nil;
                }
                // The remaining bytes are preserved
                else {
                    dataBytes += responseLength;
                    dataReceived = [[NSMutableData alloc] initWithBytes:dataBytes length:dataReceived.length - responseLength];
                }
            }
            
            CFRelease(response);
            
            break;
        }
    }
}


#pragma mark - Thread


- (void)webSocketThreadLoop {
    @autoreleasepool {
        while (state != WSWebSocketStateClosed) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 4.0, NO);
        }
    }
}


#pragma mark - Threaded methods


- (void)threadedOpen {
    [self initiateConnection];
    [self sendOpeningHandshakeWithRequest:nil];
}

- (void)threadedClose {
    [self sendCloseControlFrameWithStatusCode:1000 text:nil];
}

- (void)threadedSendData:(NSData *)data {
    WSMessage *message = [[WSMessage alloc] init];
    
    message.opcode = WSWebSocketOpcodeBinary;
    message.data = data;

    [messageProcessor queueMessage:message];
    [self sendData];
}

- (void)threadedSendText:(NSString *)text {
    WSMessage *message = [[WSMessage alloc] init];

    message.opcode = WSWebSocketOpcodeText;
    message.text = text;
    
    [messageProcessor queueMessage:message];
    [self sendData];
}

- (void)threadedSendPingWithData:(NSData *)data {
    if (state == WSWebSocketStateConnecting || state == WSWebSocketStateOpen) {
        WSFrame *frame = [[WSFrame alloc] initWithOpcode:WSWebSocketOpcodePing data:data maxSize:fragmentSize];
        [messageProcessor queueFrame:frame];
        [self sendData];
    }
}

- (void)threadedSendRequest:(NSURLRequest *)request {
    [self sendOpeningHandshakeWithRequest:request];
    [self sendData];
}


#pragma mark - Public interface


- (void)open {
    if (state != WSWebSocketStateNone) {
        return;
    }
    
    state = WSWebSocketStateConnecting;
    
    wsThread = [[NSThread alloc] initWithTarget:self selector:@selector(webSocketThreadLoop) object:nil];
    [wsThread start];
    [self performSelector:@selector(threadedOpen) onThread:wsThread withObject:nil waitUntilDone:NO];
}

- (void)close {
    [self performSelector:@selector(threadedClose) onThread:wsThread withObject:nil waitUntilDone:NO];
}

- (void)sendData:(NSData *)data {
    if (!data) {
        data = [[NSData alloc] init];
    }
    
    [self performSelector:@selector(threadedSendData:) onThread:wsThread withObject:data waitUntilDone:NO];
}

- (void)sendText:(NSString *)text {
    if (!text) {
        text = @"";
    }
    
    [self performSelector:@selector(threadedSendText:) onThread:wsThread withObject:text waitUntilDone:NO];
}

- (void)sendPingWithData:(NSData *)data {
    [self performSelector:@selector(threadedSendPingWithData:) onThread:wsThread withObject:data waitUntilDone:NO];
}

- (void)sendRequest:(NSURLRequest *)request {
    NSAssert(state == WSWebSocketStateConnecting, @"Requests can only be sent during connecting.");
    [self performSelector:@selector(threadedSendRequest:) onThread:wsThread withObject:request waitUntilDone:NO];
}

@end
