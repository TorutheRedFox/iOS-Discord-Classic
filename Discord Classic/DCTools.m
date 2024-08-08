//
//  DCWebImageOperations.m
//  Discord Classic
//
//  Created by Julian Triveri on 3/17/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import "DCTools.h"
#import "DCMessage.h"
#import "DCUser.h"
#import "DCServerCommunicator.h"
#import "DCChatVideoAttachment.h"
#import "QuickLook/QuickLook.h"
#import "UIImage+animatedGIF.h"

//https://discord.gg/X4NSsMC

@implementation DCTools
#define MAX_IMAGE_THREADS 3
static NSInteger threadQueue = 0;

static NSCache* imageCache;

static Boolean initializedDispatchQueues = NO;
static dispatch_queue_t dispatchQueues[MAX_IMAGE_THREADS];

+ (void)processImageDataWithURLString:(NSString *)urlString
														 andBlock:(void (^)(UIImage *imageData))processImage{
	
	NSURL *url = [NSURL URLWithString:urlString];
    
    if (url == nil) {
        NSLog(@"processImageDataWithURLString: nil URL encountered. Ignoring...");
        processImage(nil);
        return;
    }
    
    if (!imageCache) {
        NSLog(@"Creating image cache");
        imageCache = [[NSCache alloc] init];
    }
    
    if (!initializedDispatchQueues) {
        initializedDispatchQueues = YES;
        for (int i=0; i<MAX_IMAGE_THREADS; i++) {
            //dispatch_queue_t queue = dispatch_queue_create([[NSString stringWithFormat:@"Image Thread no. %i", i] UTF8String], DISPATCH_QUEUE_SERIAL);
            //id object = (__bridge id)queue;
            //[dispatchQueues addObject: object];
            dispatchQueues[i] = dispatch_queue_create([[NSString stringWithFormat:@"Image Thread no. %i", i] UTF8String], DISPATCH_QUEUE_SERIAL);
        }
    }
    
    UIImage *image = [imageCache objectForKey:[url absoluteString]];
    
    if (image) {
        NSLog(@"Image %@ exists in cache", [url absoluteString]);
    } else {
        NSLog(@"Image %@ doesn't exist in cache", [url absoluteString]);
    }
    
    __block id cacheWait = [imageCache objectForKey:[url absoluteString]];
    
    if (!image || ([cacheWait isKindOfClass:[NSString class]] && [cacheWait isEqualToString:@"l"])) {
        dispatch_queue_t callerQueue = dispatchQueues[threadQueue];//(__bridge dispatch_queue_t)(dispatchQueues[threadQueue]);//dispatch_get_current_queue();
        threadQueue = (threadQueue+1) % MAX_IMAGE_THREADS;

            dispatch_async(callerQueue, ^{
                //NSData* imageData = [NSData dataWithContentsOfURL:url];
                cacheWait = [imageCache objectForKey:[url absoluteString]];

                while ([cacheWait isKindOfClass:[NSString class]] && [cacheWait isEqualToString:@"l"])
                {
                    cacheWait = [imageCache objectForKey:[url absoluteString]];
                }
                
                __block UIImage *image = [imageCache objectForKey:[url absoluteString]];
                if (!image) {
                    NSLog(@"Image not cached!");
                    [imageCache setObject:@"l" forKey:[url absoluteString]]; // mark as loading
                    NSURLResponse* urlResponse;
                    NSError* error;
                    NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:15];
                    NSData* imageData = [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:&urlResponse error:&error];
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        uint8_t c;
                        [imageData getBytes:&c length:1];
                        if (c == 0x47)
                            image = [UIImage animatedImageWithAnimatedGIFData:imageData];
                        else
                            image = [UIImage imageWithData:imageData];
                        if (image != nil)
                            [imageCache setObject:image forKey:[url absoluteString]];
                        else
                            [imageCache setObject:[NSNull alloc] forKey:[url absoluteString]];
                        NSLog(@"Image added to cache");
                    });
                }
                
                if (image == nil || ![image isKindOfClass:[UIImage class]] || ![[imageCache objectForKey:[url absoluteString]] isKindOfClass:[UIImage class]]) {
                    image = nil;
                }
                
                dispatch_sync(dispatch_get_main_queue(), ^{
                    @try {
                        if ([image isKindOfClass:[UIImage class]])
                            processImage(image);
                    } @catch (id e) {
                        
                    }
                });
            });
    } else {
        NSLog(@"Image cached!");
        processImage(image);
    }
	
}

//Returns a parsed NSDictionary from a json string or nil if something goes wrong
+ (NSDictionary*)parseJSON:(NSString*)json{
    __block id parsedResponse;
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSError *error = nil;
        NSData *encodedResponseString = [json dataUsingEncoding:NSUTF8StringEncoding];
        parsedResponse = [NSJSONSerialization JSONObjectWithData:encodedResponseString options:0 error:&error];
	
    });
    if([parsedResponse isKindOfClass:NSDictionary.class]){
		return parsedResponse;
	}
	return nil;
}

+ (void)alert:(NSString*)title withMessage:(NSString*)message{
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertView *alert = [UIAlertView.alloc
													initWithTitle: title
													message: message
													delegate: nil
													cancelButtonTitle:@"OK"
													otherButtonTitles:nil];
		[alert show];
	});
}

//Used when making synchronous http requests
+ (NSData*)checkData:(NSData*)response withError:(NSError*)error{
	if(!response){
		[DCTools alert:error.localizedDescription withMessage:error.localizedRecoverySuggestion];
		return nil;
	}
	return response;
}

//Converts an NSDictionary created from json representing a user into a DCUser object
//Also keeps the user in DCServerCommunicator.loadedUsers if cache:YES
+ (DCUser*)convertJsonUser:(NSDictionary*)jsonUser cache:(bool)cache{
	
	DCUser* newUser = DCUser.new;
	newUser.username = [jsonUser valueForKey:@"username"];
    newUser.globalName = newUser.username;
    @try {
        if ([jsonUser objectForKey:@"global_name"] && [[jsonUser valueForKey:@"global_name"] isKindOfClass:[NSString class]])
            newUser.globalName = [jsonUser valueForKey:@"global_name"];
    } @catch (NSException* e) {}
	newUser.snowflake = [jsonUser valueForKey:@"id"];
    
	//Load profile image
	NSString* avatarURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/avatars/%@/%@.png?size=80", newUser.snowflake, [jsonUser valueForKey:@"avatar"]];
	[DCTools processImageDataWithURLString:avatarURL andBlock:^(UIImage *imageData){
		UIImage *retrievedImage = imageData;
		
		if(imageData){
            dispatch_async(dispatch_get_main_queue(), ^{
                newUser.profileImage = retrievedImage;
                [NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHAT DATA" object:nil];
            });
		} else {
            int selector = 0;
            NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
            [f setNumberStyle:NSNumberFormatterDecimalStyle];
            NSNumber * discriminator = [f numberFromString:[jsonUser valueForKey:@"discriminator"]];
            
            if ([discriminator integerValue] == 0) {
                NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
                [f setNumberStyle:NSNumberFormatterDecimalStyle];
                NSNumber * longId = [f numberFromString:newUser.snowflake];
                
                selector = (int)(([longId longLongValue] >> 22) % 6);
            } else {
                selector = (int)([discriminator integerValue] % 5);
            }
            newUser.profileImage = [DCUser defaultAvatars][selector];
        }
		
	}];
    
    NSString* avatarDecorationURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/avatar-decoration-presets/%@.png?size=96&passthrough=false", [jsonUser valueForKeyPath:@"avatar_decoration_data.asset"]];
	[DCTools processImageDataWithURLString:avatarDecorationURL andBlock:^(UIImage *imageData){
		UIImage *retrievedImage = imageData;
		
		if(retrievedImage != nil){
            dispatch_async(dispatch_get_main_queue(), ^{
                newUser.avatarDecoration = retrievedImage;
                [NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHAT DATA" object:nil];
            });
		}
		
	}];
	
	//Save to DCServerCommunicator.loadedUsers
	if(cache)
		[DCServerCommunicator.sharedInstance.loadedUsers setValue:newUser forKey:newUser.snowflake];
	
	return newUser;
}





//Converts an NSDictionary created from json representing a message into a message object
+ (DCMessage*)convertJsonMessage:(NSDictionary*)jsonMessage{
	DCMessage* newMessage = DCMessage.new;
	NSString* authorId = [jsonMessage valueForKeyPath:@"author.id"];
	
	if(![DCServerCommunicator.sharedInstance.loadedUsers objectForKey:authorId] && authorId != nil && authorId != [NSNull null])
		[DCTools convertJsonUser:[jsonMessage valueForKeyPath:@"author"] cache:true];
	
    // load referenced message if it exists
    float contentWidth = UIScreen.mainScreen.bounds.size.width - 63;
    
    NSDictionary* referencedJsonMessage = [jsonMessage objectForKey:@"referenced_message"];
    if ([[jsonMessage valueForKey:@"referenced_message"] isKindOfClass:[NSDictionary class]]) {
        DCMessage* referencedMessage = DCMessage.new;
        
        NSString* referencedAuthorId = [jsonMessage valueForKeyPath:@"referenced_message.author.id"];
        
        if(![DCServerCommunicator.sharedInstance.loadedUsers objectForKey:referencedAuthorId])
            [DCTools convertJsonUser:[jsonMessage valueForKeyPath:@"referenced_message.author"] cache:true];
        
        referencedMessage.author = [DCServerCommunicator.sharedInstance.loadedUsers valueForKey:referencedAuthorId];
        if ([[referencedJsonMessage valueForKey:@"content"] isKindOfClass:[NSString class]]) {
            referencedMessage.content = [referencedJsonMessage valueForKey:@"content"];
        } else {
            referencedMessage.content = @"";
        }
        referencedMessage.snowflake = [referencedJsonMessage valueForKey:@"id"];
        CGSize authorNameSize = [referencedMessage.author.globalName sizeWithFont:[UIFont boldSystemFontOfSize:10] constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT) lineBreakMode:UILineBreakModeWordWrap];
        referencedMessage.authorNameWidth = 80 + authorNameSize.width;
        
        newMessage.referencedMessage = referencedMessage;
    }
    
	newMessage.author = [DCServerCommunicator.sharedInstance.loadedUsers valueForKey:authorId];
	
	newMessage.content = [jsonMessage valueForKey:@"content"];
	newMessage.snowflake = [jsonMessage valueForKey:@"id"];
	newMessage.attachments = NSMutableArray.new;
	newMessage.attachmentCount = 0;
    
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ";
    [dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    
    newMessage.timestamp = [dateFormatter dateFromString: [jsonMessage valueForKey:@"timestamp"]];
    if (newMessage.timestamp == nil) {
        dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        newMessage.timestamp = [dateFormatter dateFromString: [jsonMessage valueForKey:@"timestamp"]];
    }
    if (newMessage.timestamp == nil)
        NSLog(@"Invalid timestamp %@", [jsonMessage valueForKey:@"timestamp"]);
    
    if ([jsonMessage valueForKey:@"edited_timestamp"] != [NSNull null]) {
        newMessage.editedTimestamp = [dateFormatter dateFromString: [jsonMessage valueForKey:@"edited_timestamp"]];
        if (newMessage.editedTimestamp == nil) {
            dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
            newMessage.editedTimestamp = [dateFormatter dateFromString: [jsonMessage valueForKey:@"edited_timestamp"]];
        }
    }
    
    NSDateFormatter *prettyDateFormatter = [NSDateFormatter new];
    
    prettyDateFormatter.dateStyle = NSDateFormatterShortStyle;
    prettyDateFormatter.timeStyle = NSDateFormatterShortStyle;
    
    prettyDateFormatter.doesRelativeDateFormatting = YES;
    
    newMessage.prettyTimestamp = [prettyDateFormatter stringFromDate:newMessage.timestamp];
    //dispatch_sync(dispatch_get_main_queue(), ^{
	//Load embeded images from both links and attatchments
	NSArray* embeds = [jsonMessage objectForKey:@"embeds"];
	if(embeds)
		for(NSDictionary* embed in embeds){
			NSString* embedType = [embed valueForKey:@"type"];
			if([embedType isEqualToString:@"image"]){
				newMessage.attachmentCount++;
                
                NSString *attachmentURL = [[embed valueForKey:@"url"] stringByReplacingOccurrencesOfString:@"cdn.discordapp.com" withString:@"media.discordapp.net"];
                
                if ([embed valueForKey:@"image.url"] != nil) {
                    attachmentURL = [[embed valueForKey:@"image.url"] stringByReplacingOccurrencesOfString:@"cdn.discordapp.com" withString:@"media.discordapp.net"];
                }
                
                if ([embed valueForKey:@"image.proxy_url"] != nil) {
                    attachmentURL = [[embed valueForKey:@"image.proxy_url"] stringByReplacingOccurrencesOfString:@"cdn.discordapp.com" withString:@"media.discordapp.net"];
                }
                
                NSInteger width = [[embed valueForKey:@"image.width"] integerValue];
                NSInteger height = [[embed valueForKey:@"image.height"] integerValue];
                CGFloat aspectRatio = (CGFloat)width / (CGFloat)height;
                
                if (height > 1024) {
                    height = 1024;
                    width = height * aspectRatio;
                    if (width > 1024) {
                        width = 1024;
                        height = width / aspectRatio;
                    }
                } else if (width > 1024) {
                    width = 1024;
                    height = width / aspectRatio;
                    if (height > 1024) {
                        height = 1024;
                        width = height * aspectRatio;
                    }
                }
                
                NSString *urlString = attachmentURL;
                
                if (width != 0 || height != 0) {
                    if ([urlString rangeOfString:@"?"].location == NSNotFound)
                        urlString = [NSString stringWithFormat:@"%@?width=%d&height=%d", urlString, width, height];
                    else
                        urlString = [NSString stringWithFormat:@"%@&width=%d&height=%d", urlString, width, height];
                }
                
                
                [DCTools processImageDataWithURLString:urlString andBlock:^(UIImage *imageData){
                    UIImage *retrievedImage = imageData;
                    
                    if(retrievedImage != nil){
                        [newMessage.attachments addObject:retrievedImage];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHAT DATA" object:nil];
                        });
                    }
                }];
			} else if ([embedType isEqualToString:@"video"] || [embedType isEqualToString:@"gifv"]) {
                newMessage.attachmentCount++;
                
                NSURL *attachmentURL = [NSURL URLWithString:[embed valueForKey:@"url"]];
                
                if ([embed valueForKey:@"video.proxy_url"] != nil && [[embed valueForKey:@"video.proxy_url"] isKindOfClass:[NSString class]]) {
                    attachmentURL = [NSURL URLWithString:[embed valueForKey:@"video.proxy_url"]];
                } else if ([embed valueForKey:@"video.url"] != nil && [[embed valueForKey:@"video.url"] isKindOfClass:[NSString class]]) {
                    attachmentURL = [NSURL URLWithString:[embed valueForKey:@"video.url"]];
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    //[newMessage.attachments addObject:[[MPMoviePlayerViewController alloc] initWithContentURL:attachmentURL]];
                    DCChatVideoAttachment *video = [[[NSBundle mainBundle] loadNibNamed:@"DCChatVideoAttachment" owner:self options:nil] objectAtIndex:0];
                    
                    video.videoURL = attachmentURL;
                    
                    NSString *baseURL = [[embed valueForKey:@"url"] stringByReplacingOccurrencesOfString:@"cdn.discordapp.com" withString:@"media.discordapp.net"];
                    
                    
                    if ([embed valueForKey:@"video.proxy_url"] != nil && [[embed valueForKey:@"video.proxy_url"] isKindOfClass:[NSString class]]) {
                        baseURL = [[embed valueForKey:@"video.proxy_url"] stringByReplacingOccurrencesOfString:@"cdn.discordapp.com" withString:@"media.discordapp.net"];
                    } else if ([embed valueForKey:@"video.url"] != nil && [[embed valueForKey:@"video.url"] isKindOfClass:[NSString class]]) {
                        baseURL = [[embed valueForKey:@"video.url"] stringByReplacingOccurrencesOfString:@"cdn.discordapp.com" withString:@"media.discordapp.net"];
                    }
                    
                    NSInteger width = [[embed valueForKey:@"video.width"] integerValue];
                    NSInteger height = [[embed valueForKey:@"video.height"] integerValue];
                    CGFloat aspectRatio = (CGFloat)width / (CGFloat)height;
                    
                    if (height > 1024) {
                        height = 1024;
                        width = height * aspectRatio;
                        if (width > 1024) {
                            width = 1024;
                            height = width / aspectRatio;
                        }
                    } else if (width > 1024) {
                        width = 1024;
                        height = width / aspectRatio;
                        if (height > 1024) {
                            height = 1024;
                            width = height * aspectRatio;
                        }
                    }
                    
                    NSString *urlString = baseURL;
                    
                    if (width != 0 || height != 0) {
                        if ([urlString rangeOfString:@"?"].location == NSNotFound)
                            urlString = [NSString stringWithFormat:@"%@?format=jpeg&width=%d&height=%d", urlString, width, height];
                        else
                            urlString = [NSString stringWithFormat:@"%@&format=jpeg&width=%d&height=%d", urlString, width, height];
                    } else {
                        if ([urlString rangeOfString:@"?"].location == NSNotFound)
                            urlString = [NSString stringWithFormat:@"%@?format=jpeg", urlString];
                        else
                            urlString = [NSString stringWithFormat:@"%@&format=jpeg", urlString];
                    }
                    
                    [DCTools processImageDataWithURLString:urlString andBlock:^(UIImage *imageData){
                        UIImage *retrievedImage = imageData;
                        
                        if(retrievedImage != nil && [retrievedImage isKindOfClass:[UIImage class]]) {
                            [video.thumbnail setImage:retrievedImage];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHAT DATA" object:nil];
                            });
                        } else {
                            NSLog(@"Failed to load video thumbnail!");
                        }
                    }];
                    
                    video.layer.cornerRadius = 6;
                    video.layer.masksToBounds = YES;
                    video.userInteractionEnabled = YES;
                    [newMessage.attachments addObject:video];
                });
            } else {
                NSLog(@"unknown embed type %@", embedType);
                continue;
            }
		}
	
	NSArray* attachments = [jsonMessage objectForKey:@"attachments"];
	if(attachments)
		for(NSDictionary* attachment in attachments){
            NSString *fileType = [attachment valueForKey:@"content_type"];
            if ([fileType rangeOfString:@"image/"].location != NSNotFound) {
                newMessage.attachmentCount++;
                
                NSString *attachmentURL = [[attachment valueForKey:@"url"] stringByReplacingOccurrencesOfString:@"cdn.discordapp.com" withString:@"media.discordapp.net"];
                
                NSInteger width = [[attachment valueForKey:@"width"] integerValue];
                NSInteger height = [[attachment valueForKey:@"height"] integerValue];
                CGFloat aspectRatio = (CGFloat)width / (CGFloat)height;
                
                if (height > 1024) {
                    height = 1024;
                    width = height * aspectRatio;
                    if (width > 1024) {
                        width = 1024;
                        height = width / aspectRatio;
                    }
                } else if (width > 1024) {
                    width = 1024;
                    height = width / aspectRatio;
                    if (height > 1024) {
                        height = 1024;
                        width = height * aspectRatio;
                    }
                }
                
                NSString *urlString = [NSString stringWithFormat:@"%@&width=%ld&height=%ld", attachmentURL, (long)width, (long)height];
                if ([attachmentURL rangeOfString:@"?"].location == NSNotFound)
                    urlString = [NSString stringWithFormat:@"%@?width=%ld&height=%ld", attachmentURL, (long)width, (long)height];
                
                
                [DCTools processImageDataWithURLString:urlString andBlock:^(UIImage *imageData){
                    UIImage *retrievedImage = imageData;
                    
                    if(retrievedImage != nil){
                        [newMessage.attachments addObject:retrievedImage];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHAT DATA" object:nil];
                        });
                    }
                }];
            } else if ([fileType rangeOfString:@"video/"].location != NSNotFound) {
                newMessage.attachmentCount++;
                
                NSURL *attachmentURL = [NSURL URLWithString:[attachment valueForKey:@"url"]];
                dispatch_async(dispatch_get_main_queue(), ^{
                    //[newMessage.attachments addObject:[[MPMoviePlayerViewController alloc] initWithContentURL:attachmentURL]];
                    DCChatVideoAttachment *video = [[[NSBundle mainBundle] loadNibNamed:@"DCChatVideoAttachment" owner:self options:nil] objectAtIndex:0];
                    
                    video.videoURL = attachmentURL;
                    
                    NSString *baseURL = [[attachment valueForKey:@"url"] stringByReplacingOccurrencesOfString:@"cdn.discordapp.com" withString:@"media.discordapp.net"];
                    
                    NSInteger width = [[attachment valueForKey:@"width"] integerValue];
                    NSInteger height = [[attachment valueForKey:@"height"] integerValue];
                    CGFloat aspectRatio = (CGFloat)width / (CGFloat)height;
                    
                    if (height > 1024) {
                        height = 1024;
                        width = height * aspectRatio;
                        if (width > 1024) {
                            width = 1024;
                            height = width / aspectRatio;
                        }
                    } else if (width > 1024) {
                        width = 1024;
                        height = width / aspectRatio;
                        if (height > 1024) {
                            height = 1024;
                            width = height * aspectRatio;
                        }
                    }

                    
                    NSString *urlString = [NSString stringWithFormat:@"%@format=jpeg&width=%d&height=%d", baseURL, width, height];
                    if ([baseURL rangeOfString:@"?"].location == NSNotFound)
                        urlString = [NSString stringWithFormat:@"%@?format=jpeg&width=%d&height=%d", baseURL, width, height];
                    
                    
                    [DCTools processImageDataWithURLString:urlString andBlock:^(UIImage *imageData){
                        UIImage *retrievedImage = imageData;
                        
                        if(retrievedImage != nil){
                            [video.thumbnail setImage:retrievedImage];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHAT DATA" object:nil];
                            });
                        } else {
                            NSLog(@"Failed to load video thumbnail!");
                        }
                    }];
                    
                    video.layer.cornerRadius = 6;
                    video.layer.masksToBounds = YES;
                    video.userInteractionEnabled = YES;
                    [newMessage.attachments addObject:video];
                });
            } else {
                NSLog(@"unknown attachment type %@", fileType);
                newMessage.content = [NSString stringWithFormat:@"%@\n%@", newMessage.content, [attachment valueForKey:@"url"]];
                continue;
            }
		}
    //});
	
	//Parse in-text mentions into readable @<username>
	NSArray* mentions = [jsonMessage objectForKey:@"mentions"];
	
	if(mentions.count){
		
		for(NSDictionary* mention in mentions){
			if(![DCServerCommunicator.sharedInstance.loadedUsers valueForKey:[mention valueForKey:@"id"]]){
				[DCTools convertJsonUser:mention cache:true];
			}
		}
		
		NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\<@(.*?)\\>" options:NSRegularExpressionCaseInsensitive error:NULL];
		
		NSTextCheckingResult *embededMention = [regex firstMatchInString:newMessage.content options:0 range:NSMakeRange(0, newMessage.content.length)];
		
		while(embededMention){
			
			NSCharacterSet *charactersToRemove = [NSCharacterSet.alphanumericCharacterSet invertedSet];
			NSString *mentionSnowflake = [[[newMessage.content substringWithRange:embededMention.range] componentsSeparatedByCharactersInSet:charactersToRemove] componentsJoinedByString:@""];
			
			if([mentionSnowflake isEqualToString: DCServerCommunicator.sharedInstance.snowflake])
				newMessage.pingingUser = true;
			
			DCUser *user = [DCServerCommunicator.sharedInstance.loadedUsers valueForKey:mentionSnowflake];
			
			NSString* username = @"@MENTION";
			
			if(user)
				username = [NSString stringWithFormat:@"@%@", user.username];
			
			newMessage.content = [newMessage.content stringByReplacingCharactersInRange:embededMention.range withString:username];
			
			embededMention = [regex firstMatchInString:newMessage.content options:0 range:NSMakeRange(0, newMessage.content.length)];
		}
	}
	
	//Calculate height of content to be used when showing messages in a tableview
	//contentHeight does NOT include height of the embeded images or account for height of a grouped message
	
	CGSize authorNameSize = [newMessage.author.globalName sizeWithFont:[UIFont boldSystemFontOfSize:15] constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT) lineBreakMode:UILineBreakModeWordWrap];
	CGSize contentSize = [newMessage.content sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(contentWidth, MAXFLOAT) lineBreakMode:UILineBreakModeWordWrap];
    
    newMessage.contentHeight = authorNameSize.height + contentSize.height + 10 + (newMessage.referencedMessage != nil ? 16 : 0);
    newMessage.authorNameWidth = 60 + authorNameSize.width;
	
	return newMessage;
}





+(DCGuild *)convertJsonGuild:(NSDictionary*)jsonGuild{
	NSMutableArray* userRoles;
	
	//Get roles of the current user
	for(NSDictionary* member in [jsonGuild objectForKey:@"members"])
		if([[member valueForKeyPath:@"user.id"] isEqualToString:DCServerCommunicator.sharedInstance.snowflake])
			userRoles = [[member valueForKey:@"roles"] mutableCopy];
	
	//Get @everyone role
	for(NSDictionary* guildRole in [jsonGuild objectForKey:@"roles"])
		if([[guildRole valueForKey:@"name"] isEqualToString:@"@everyone"])
			[userRoles addObject:[guildRole valueForKey:@"id"]];
	
	DCGuild* newGuild = DCGuild.new;
	newGuild.name = [jsonGuild valueForKey:@"name"];
	newGuild.snowflake = [jsonGuild valueForKey:@"id"];
	newGuild.channels = NSMutableArray.new;
    
	NSString* iconURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/icons/%@/%@.png?size=80",
											 newGuild.snowflake, [jsonGuild valueForKey:@"icon"]];
	
    NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
    [f setNumberStyle:NSNumberFormatterDecimalStyle];
    NSNumber * longId = [f numberFromString:newGuild.snowflake];
    
    int selector = (int)(([longId longLongValue] >> 22) % 6);
    
    newGuild.icon = [DCUser defaultAvatars][selector];
    /*CGSize itemSize = CGSizeMake(40, 40);
    UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
    CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
    [newGuild.icon  drawInRect:imageRect];
    newGuild.icon = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();*/
    
	[DCTools processImageDataWithURLString:iconURL andBlock:^(UIImage *imageData) {
        UIImage* icon = imageData;
        
        if (icon != nil) {
            newGuild.icon = icon;
            CGSize itemSize = CGSizeMake(40, 40);
            UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
            CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
            [newGuild.icon  drawInRect:imageRect];
            newGuild.icon = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
		
		dispatch_async(dispatch_get_main_queue(), ^{
			[NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD GUILD LIST" object:DCServerCommunicator.sharedInstance];
		});
		
	}];
	
	for(NSDictionary* jsonChannel in [jsonGuild valueForKey:@"channels"]){
		
		//Make sure jsonChannel is a text cannel
		//we dont want to include voice channels in the text channel list
		if([[jsonChannel valueForKey:@"type"] isEqual: @0]){
			
			//Allow code is used to determine if the user should see the channel in question.
			/*
			 0 - No overwrides. Channel should be created
			 
			 1 - Hidden by role. Channel should not be created unless another role contradicts (code 2)
			 2 - Shown by role. Channel should be created unless hidden by member overwride (code 3)
			 
			 3 - Hidden by member. Channel should not be created
			 4 - Shown by member. Channel should be created
			 
			 3 & 4 are mutually exclusive
			 */
			int allowCode = 0;
			
			//Calculate permissions
			for(NSDictionary* permission in [jsonChannel objectForKey:@"permission_overwrites"]){
				
				//Type of permission can either be role or member
				int type = [permission valueForKey:@"type"];
				
				if(type == 0) {//if([type isEqualToString:@"role"]){
					
					//Check if this channel dictates permissions over any roles the user has
					if([userRoles containsObject:[permission valueForKey:@"id"]]){
						int deny = [[permission valueForKey:@"deny"] intValue];
						int allow = [[permission valueForKey:@"allow"] intValue];
						
						if((deny & 1024) == 1024 && allowCode < 1)
							allowCode = 1;
						
						if(((allow & 1024) == 1024) && allowCode < 2)
							allowCode = 2;
					}
				}
				
				
				if(type == 1){//if([type isEqualToString:@"member"]){
					
					//Check if
					NSString* memberId = [permission valueForKey:@"id"];
					if([memberId isEqualToString:DCServerCommunicator.sharedInstance.snowflake]){
						int deny = [[permission valueForKey:@"deny"] intValue];
						int allow = [[permission valueForKey:@"allow"] intValue];
						
						if((deny & 1024) == 1024 && allowCode < 3)
							allowCode = 3;
						
						if((allow & 1024) == 1024){
							allowCode = 4;
							break;
						}
					}
				}
			}
			
			if(allowCode == 0 || allowCode == 2 || allowCode == 4){
				DCChannel* newChannel = DCChannel.new;
				
				newChannel.snowflake = [jsonChannel valueForKey:@"id"];
				newChannel.name = [jsonChannel valueForKey:@"name"];
				newChannel.lastMessageId = [jsonChannel valueForKey:@"last_message_id"];
				newChannel.parentGuild = newGuild;
				newChannel.type = 0;
				
				if([DCServerCommunicator.sharedInstance.userChannelSettings objectForKey:newChannel.snowflake])
					newChannel.muted = true;
				
				//check if channel is muted
				
				[newGuild.channels addObject:newChannel];
				[DCServerCommunicator.sharedInstance.channels setObject:newChannel forKey:newChannel.snowflake];
			}
		}
	}
	
	return newGuild;
}





+ (void)joinGuild:(NSString*)inviteCode {
    //dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		NSURL* guildURL = [NSURL URLWithString: [NSString stringWithFormat:@"https://discordapp.com/api/v9/invite/%@", inviteCode]];
        
		NSMutableURLRequest *urlRequest=[NSMutableURLRequest requestWithURL:guildURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
        [urlRequest setValue:@"no-store" forHTTPHeaderField:@"Cache-Control"];
		
		[urlRequest setHTTPMethod:@"POST"];
		
		//[urlRequest setHTTPBody:[NSData dataWithBytes:[messageString UTF8String] length:[messageString length]]];
		[urlRequest addValue:DCServerCommunicator.sharedInstance.token forHTTPHeaderField:@"Authorization"];
		[urlRequest addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		
		/*NSError *error = nil;
		NSHTTPURLResponse *responseCode = nil;
        int attempts = 0;
        while (attempts == 0 || (attempts <= 10 && error.code == NSURLErrorTimedOut)) {
            attempts++;
            error = nil;
            [UIApplication sharedApplication].networkActivityIndicatorVisible++;
            [DCTools checkData:[NSURLConnection sendSynchronousRequest:urlRequest returningResponse:&responseCode error:&error] withError:error];
            [UIApplication sharedApplication].networkActivityIndicatorVisible--;*/
    dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].networkActivityIndicatorVisible++;
    });
            [NSURLConnection sendAsynchronousRequest:urlRequest queue:[NSOperationQueue currentQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connError) {
                dispatch_sync(dispatch_get_main_queue(), ^{
                    if ([UIApplication sharedApplication].networkActivityIndicatorVisible > 0)
                        [UIApplication sharedApplication].networkActivityIndicatorVisible--;
                    else if ([UIApplication sharedApplication].networkActivityIndicatorVisible < 0)
                        [UIApplication sharedApplication].networkActivityIndicatorVisible = 0;
                });

            }];
        //}
    //});
}

@end