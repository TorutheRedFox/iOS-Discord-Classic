//
//  DCServerCommunicator.m
//  Discord Classic
//
//  Created by Julian Triveri on 3/4/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import "DCServerCommunicator.h"
#import "DCGuild.h"
#import "DCChannel.h"
#import "DCTools.h"

@interface DCServerCommunicator()
@property (strong, nonatomic) UIView *notificationView;
@property bool didRecieveHeartbeatResponse;
@property bool didTryResume;
@property bool shouldResume;
@property bool heartbeatDefined;

@property bool identifyCooldown;

@property int sequenceNumber;
@property NSString* sessionId;

@property NSTimer* cooldownTimer;
@property UIAlertView* alertView;
+ (DCServerCommunicator *)sharedInstance;
- (void)showNonIntrusiveNotificationWithTitle:(NSString *)title;
- (void)dismissNotification;
@end


@implementation DCServerCommunicator

UIActivityIndicatorView *spinner;

+ (DCServerCommunicator *)sharedInstance {
    
    static DCServerCommunicator *sharedInstance = nil;
    
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        
        sharedInstance = [[self alloc] init];
        
        // Initialize if a sharedInstance does not yet exist
        
        sharedInstance.gatewayURL = @"wss://gateway.discord.gg/?encoding=json&v=9";
        
        sharedInstance.token = [[NSUserDefaults standardUserDefaults] stringForKey:@"token"];
        
        [sharedInstance showNonIntrusiveNotificationWithTitle:@"Connecting"];
        
    });
    
    return sharedInstance;
    
}


- (void)showNonIntrusiveNotificationWithTitle:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
        CGFloat notificationWidth = screenWidth - 130; // Increased padding to 60 points on each side
        CGFloat notificationHeight = 40;
        CGFloat notificationX = (screenWidth - notificationWidth) / 2; // Center the notification
        CGFloat notificationY = -notificationHeight; // Start above the visible screen area
        
        if (self.notificationView != nil) {
            [self.notificationView removeFromSuperview]; // Remove existing view if any
            self.notificationView = nil;
        }
        
        self.notificationView = [[UIView alloc] initWithFrame:CGRectMake(notificationX, notificationY, notificationWidth, notificationHeight)];
        self.notificationView.backgroundColor = [UIColor grayColor]; // Background color
        self.notificationView.layer.cornerRadius = 13; // Rounded corners
        self.notificationView.layer.masksToBounds = YES;
        
        // Create and configure the label for the notification with dynamic title
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, notificationWidth, notificationHeight)];
        label.text = title; // Use the passed title
        label.textColor = [UIColor blackColor]; // Text color
        label.textAlignment = NSTextAlignmentCenter;
        
        // Create and position the activity indicator
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        spinner.center = CGPointMake(notificationWidth - 30, notificationHeight / 2); // Position spinner
        [spinner startAnimating];
        
        // Add the label and spinner to the notification view
        [self.notificationView addSubview:label];
        [self.notificationView addSubview:spinner];
        
        // Add the notification view to the window
        UIWindow *window = [[[UIApplication sharedApplication] windows] lastObject];
        [window addSubview:self.notificationView];
        
        // Animate the notification to slide in from the top
        [UIView animateWithDuration:0.6 animations:^{
            self.notificationView.frame = CGRectMake(notificationX, 72, notificationWidth, notificationHeight); // Move to the final position
        }];
    });
}

- (void)dismissNotification {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Animate out
        [UIView animateWithDuration:0.4 animations:^{
            CGRect frame = self.notificationView.frame;
            frame.origin.y = -frame.size.height; // Move off-screen
            self.notificationView.frame = frame;
        } completion:^(BOOL finished) {
            [self.notificationView removeFromSuperview];
            self.notificationView = nil;
        }];
    });
}


- (DCChannel *)findChannelById:(NSString *)channelId {
    for (DCGuild *guild in self.guilds) { // Replace `self.guilds` with your guilds array
        for (DCChannel *channel in guild.channels) {
            if ([channel.snowflake isEqualToString:channelId]) {
                return channel;
            }
        }
    }
    return nil;
}

- (void)startCommunicator{
	
	[self.alertView show];
    if (spinner == nil)
        spinner = [UIActivityIndicatorView.alloc initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    [spinner setCenter:CGPointMake(139.5, 57.5)];
    
    [self.alertView addSubview:spinner];
    [spinner startAnimating];
	
	self.didAuthenticate = false;
	
	if(self.token!=nil){
		
		//Establish websocket connection with Discord
		NSURL *websocketUrl = [NSURL URLWithString:self.gatewayURL];
		self.websocket = [WSWebSocket.alloc initWithURL:websocketUrl protocols:nil];
		
		//To prevent retain cycle
		__weak typeof(self) weakSelf = self;
		
		[self.websocket setTextCallback:^(NSString *responseString) {
			
			//Parse JSON to a dictionary
			NSDictionary *parsedJsonResponse = [DCTools parseJSON:responseString];
			
			//Data values for easy access
			int op = [[parsedJsonResponse valueForKey:@"op"] integerValue];
			NSDictionary* d = [parsedJsonResponse valueForKey:@"d"];
			
			NSLog(@"Got op code %i", op);
			
			//revcieved HELLO eventd
			switch(op){
					
				case 10: {
					
					if(weakSelf.shouldResume){
						NSLog(@"Sending Resume with sequence number %i, session ID %@", weakSelf.sequenceNumber, weakSelf.sessionId);
						
						//RESUME
						[weakSelf sendJSON:@{
                                             @"op":@6,
                                             @"d":@{
                                                     @"token":weakSelf.token,
                                                     @"session_id":weakSelf.sessionId,
                                                     @"seq":@(weakSelf.sequenceNumber),
                                                     }
                                             }];
						
						weakSelf.shouldResume = false;
						
					}else{
						
						NSLog(@"Sending Identify");
						
						//IDENTIFY
						[weakSelf sendJSON:@{
                                             @"op":@2,
                                             @"d":@{
                                                     @"token":weakSelf.token,
                                                     @"properties":@{
                                                             @"os" : @"iOS",
                                                             @"$browser" : @"Discord iOS",
                                                             },
                                                     @"large_threshold":@"50",
                                                     }
                                             }];
						
						//Disable ability to identify until reenabled 5 seconds later.
						//API only allows once identify every 5 seconds
						weakSelf.identifyCooldown = false;
						
						weakSelf.guilds = NSMutableArray.new;
						weakSelf.channels = NSMutableDictionary.new;
						weakSelf.loadedUsers = NSMutableDictionary.new;
						weakSelf.didRecieveHeartbeatResponse = true;
                        if ([UIApplication sharedApplication].networkActivityIndicatorVisible > 0)
                            [UIApplication sharedApplication].networkActivityIndicatorVisible--;
                        else if ([UIApplication sharedApplication].networkActivityIndicatorVisible < 0)
                            [UIApplication sharedApplication].networkActivityIndicatorVisible = 0;
						
						int heartbeatInterval = [[d valueForKey:@"heartbeat_interval"] intValue];
						
						dispatch_async(dispatch_get_main_queue(), ^{
							
							static dispatch_once_t once;
							dispatch_once(&once, ^ {
								
								NSLog(@"Heartbeat is %d seconds", heartbeatInterval/1000);
								
								//Begin heartbeat cycle if not already begun
								[NSTimer scheduledTimerWithTimeInterval:heartbeatInterval/1000 target:weakSelf selector:@selector(sendHeartbeat:) userInfo:nil repeats:YES];
							});
							
							//Reenable ability to identify in 5 seconds
							weakSelf.cooldownTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:weakSelf selector:@selector(refreshIdentifyCooldown:) userInfo:nil repeats:NO];
						});
						
					}
					
				}
					break;
					
					
					//Misc Event
				case 0: {
					
					//Get event type and sequence number
					NSString* t = [parsedJsonResponse valueForKey:@"t"];
					weakSelf.sequenceNumber = [[parsedJsonResponse valueForKey:@"s"] integerValue];
					
					NSLog(@"Got event %@ with sequence number %i", t, weakSelf.sequenceNumber);
					
					//recieved READY
                    if(![[parsedJsonResponse valueForKey:@"t"] isKindOfClass:[NSString class]]) {
                        
                    } else if([t isEqualToString:@"READY"]){
						dispatch_async(dispatch_get_main_queue(), ^{
                            weakSelf.didAuthenticate = true;
                            NSLog(@"Did authenticate!");
                            [weakSelf dismissNotification];
                            
                            //Grab session id (used for RESUME) and user id
                            weakSelf.sessionId = [NSString stringWithFormat:@"%@", [d valueForKeyPath:@"session_id"]];
                            weakSelf.snowflake = [NSString stringWithFormat:@"%@", [d valueForKeyPath:@"user.id"]];
                            
                            weakSelf.userChannelSettings = NSMutableDictionary.new;
                            for(NSDictionary* guildSettings in [d valueForKey:@"user_guild_settings"])
                                for(NSDictionary* channelSetting in [guildSettings objectForKey:@"channel_overrides"])
                                    [weakSelf.userChannelSettings setValue:@((bool)[channelSetting valueForKey:@"muted"]) forKey:[channelSetting valueForKey:@"channel_id"]];
                            
                            //Get user DMs and DM groups
                            //The user's DMs are treated like a guild, where the channels are different DM/groups
                            DCGuild* privateGuild = DCGuild.new;
                            privateGuild.name = @"Direct Messages";
                            privateGuild.icon = [UIImage imageNamed:@"DefaultAvatar0"];
                            privateGuild.channels = NSMutableArray.new;
                            
                            for(NSDictionary* privateChannel in [d valueForKey:@"private_channels"]){
                                
                                //this may actually suck
                                // Initialize users array for the member list
                                NSMutableArray *users = NSMutableArray.new;
                                NSMutableDictionary *usersDict;
                                for (NSDictionary* user in [privateChannel objectForKey:@"recipients"]) {
                                    usersDict = NSMutableDictionary.new;
                                    [usersDict setObject:[user valueForKey:@"global_name"] forKey:@"global_name"];
                                    [usersDict setObject:[user valueForKey:@"avatar"] forKey:@"avatar"];
                                    [usersDict setObject:[user valueForKey:@"discriminator"] forKey:@"discriminator"];
                                    [users addObject:usersDict];
                                }
                                // Add self to users list
                                usersDict = NSMutableDictionary.new;
                                [usersDict setObject:@"You" forKey:@"global_name"];
                                [usersDict setObject:@"TEMP" forKey:@"avatar"];
                                [users addObject:usersDict];
                                //end
                                
                                DCChannel* newChannel = DCChannel.new;
                                newChannel.snowflake = [privateChannel valueForKey:@"id"];
                                newChannel.lastMessageId = [privateChannel valueForKey:@"last_message_id"];
                                newChannel.parentGuild = privateGuild;
                                newChannel.type = 1;
                                newChannel.users = users;
                                if ([privateChannel objectForKey:@"icon"] != nil || [privateChannel objectForKey:@"recipients"] != nil) {
                                    if (((NSArray*)[privateChannel valueForKey:@"recipients"]).count > 0) {
                                        NSDictionary *user = [[privateChannel valueForKey:@"recipients"] objectAtIndex:0];
                                        NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
                                        [f setNumberStyle:NSNumberFormatterDecimalStyle];
                                        NSNumber * longId = [f numberFromString:[user valueForKey:@"id"]];
                                        
                                        int selector = (int)(([longId longLongValue] >> 22) % 6);
                                        
                                        newChannel.icon = [DCUser defaultAvatars][selector];
                                        CGSize itemSize = CGSizeMake(32, 32);
                                        UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                                        CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                                        [newChannel.icon  drawInRect:imageRect];
                                        newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                                    }
                                    if ([privateChannel objectForKey:@"icon"] != nil) {
                                        NSString* iconURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/channel-icons/%@/%@.png?size=64",
                                                             newChannel.snowflake, [privateChannel valueForKey:@"icon"]];
                                        
                                        NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
                                        [f setNumberStyle:NSNumberFormatterDecimalStyle];
                                        NSNumber * longId = [f numberFromString:newChannel.snowflake];
                                        
                                        int selector = (int)(([longId longLongValue] >> 22) % 6);
                                        
                                        newChannel.icon = [DCUser defaultAvatars][selector];
                                        CGSize itemSize = CGSizeMake(32, 32);
                                        UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                                        CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                                        [newChannel.icon  drawInRect:imageRect];
                                        newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                                        UIGraphicsEndImageContext();
                                        
                                        [DCTools processImageDataWithURLString:iconURL andBlock:^(UIImage *imageData) {
                                            UIImage* icon = imageData;
                                            
                                            if (icon != nil) {
                                                newChannel.icon = icon;
                                                CGSize itemSize = CGSizeMake(32, 32);
                                                UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                                                CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                                                [newChannel.icon  drawInRect:imageRect];
                                                newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                                                UIGraphicsEndImageContext();
                                            }
                                            
                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                /*[NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHANNEL LIST" object:DCServerCommunicator.sharedInstance];*/
                                            });
                                            
                                        }];
                                    } else {
                                        if (((NSArray*)[privateChannel valueForKey:@"recipients"]).count > 0) {
                                            NSDictionary *user = [[privateChannel valueForKey:@"recipients"] objectAtIndex:0];
                                            NSString* avatarURL = [NSString stringWithFormat:@"https://cdn.discordapp.com/avatars/%@/%@.png?size=64", [user  valueForKey:@"id"], [user valueForKey:@"avatar"]];
                                            [DCTools processImageDataWithURLString:avatarURL andBlock:^(UIImage *imageData){
                                                UIImage *retrievedImage = imageData;
                                                
                                                if(imageData){
                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                        newChannel.icon = retrievedImage;
                                                        CGSize itemSize = CGSizeMake(32, 32);
                                                        UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                                                        CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                                                        [newChannel.icon  drawInRect:imageRect];
                                                        newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                                                        [NSNotificationCenter.defaultCenter postNotificationName:@"RELOAD CHANNEL LIST" object:nil];
                                                    });
                                                } else {
                                                    int selector = 0;
                                                    NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
                                                    [f setNumberStyle:NSNumberFormatterDecimalStyle];
                                                    NSNumber * discriminator = [f numberFromString:[user valueForKey:@"discriminator"]];
                                                    
                                                    if ([discriminator integerValue] == 0) {
                                                        NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
                                                        [f setNumberStyle:NSNumberFormatterDecimalStyle];
                                                        NSNumber * longId = [f numberFromString:[user  valueForKey:@"id"]];
                                                        
                                                        selector = (int)(([longId longLongValue] >> 22) % 6);
                                                    } else {
                                                        selector = (int)([discriminator integerValue] % 5);
                                                    }
                                                    newChannel.icon = [DCUser defaultAvatars][selector];
                                                    CGSize itemSize = CGSizeMake(32, 32);
                                                    UIGraphicsBeginImageContextWithOptions(itemSize, NO, UIScreen.mainScreen.scale);
                                                    CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
                                                    [newChannel.icon  drawInRect:imageRect];
                                                    newChannel.icon = UIGraphicsGetImageFromCurrentImageContext();
                                                    UIGraphicsEndImageContext();
                                                }
                                                
                                            }];
                                        }
                                    }
                                    
                                }
                                
                                NSString* privateChannelName = [privateChannel valueForKey:@"name"];
                                
                                //Some private channels dont have names, check if nil
                                if(privateChannelName && privateChannelName != (id)NSNull.null){
                                    newChannel.name = privateChannelName;
                                }else{
                                    //If no name, create a name from channel members
                                    NSMutableString* fullChannelName = [@"@" mutableCopy];
                                    
                                    NSArray* privateChannelMembers = [privateChannel valueForKey:@"recipients"];
                                    for(NSDictionary* privateChannelMember in privateChannelMembers){
                                        //add comma between member names
                                        if([privateChannelMembers indexOfObject:privateChannelMember] != 0)
                                            [fullChannelName appendString:@", @"];
                                        
                                        NSString* memberName = [privateChannelMember valueForKey:@"username"];
                                        @try {
                                            if ([privateChannelMember objectForKey:@"global_name"] &&  [[privateChannelMember valueForKey:@"global_name"] isKindOfClass:[NSString class]])
                                                memberName = [privateChannelMember valueForKey:@"global_name"];
                                        } @catch (NSException* e) {}
                                        
                                        [fullChannelName appendString:memberName];
                                        
                                        newChannel.name = fullChannelName;
                                    }
                                }
                                
                                [privateGuild.channels addObject:newChannel];
                            }
                            // Sort the DMs list by most recent...
                            NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"lastMessageId" ascending:NO selector:@selector(localizedStandardCompare:)];
                            [privateGuild.channels sortUsingDescriptors:@[sortDescriptor]];
                            for (DCChannel *channel in privateGuild.channels) {
                                [weakSelf.channels setObject:channel forKey:channel.snowflake];
                            }
                            
                            [weakSelf.guilds addObject:privateGuild];
                            
                            
                            //Get servers (guilds) the user is a member of
                            for(NSDictionary* jsonGuild in [d valueForKey:@"guilds"])
                                [weakSelf.guilds addObject:[DCTools convertJsonGuild:jsonGuild]];
                            
                            
                            //Read states are recieved in READY payload
                            //they give a channel ID and the ID of the last read message in that channel
                            NSArray* readstatesArray = [d valueForKey:@"read_state"];
                            
                            for(NSDictionary* readstate in readstatesArray){
                                
                                NSString* readstateChannelId = [readstate valueForKey:@"id"];
                                NSString* readstateMessageId = [readstate valueForKey:@"last_message_id"];
                                
                                //Get the channel with the ID of readStateChannelId
                                DCChannel* channelOfReadstate = [weakSelf.channels objectForKey:readstateChannelId];
                                
                                channelOfReadstate.lastReadMessageId = readstateMessageId;
                                [channelOfReadstate checkIfRead];
                            }
                            
                            //dispatch_async(dispatch_get_main_queue(), ^{
							[NSNotificationCenter.defaultCenter postNotificationName:@"READY" object:weakSelf];
							
							//Dismiss the 'reconnecting' dialogue box
							[weakSelf.alertView dismissWithClickedButtonIndex:0 animated:YES];
                            //});
                        });
					}
					
					if([t isEqualToString:@"RESUMED"]){
						weakSelf.didAuthenticate = true;
						dispatch_async(dispatch_get_main_queue(), ^{
							[weakSelf dismissNotification];
						});
					}
					
					if([t isEqualToString:@"MESSAGE_CREATE"]){
						dispatch_async(dispatch_get_main_queue(), ^{
                            NSString* channelIdOfMessage = [d objectForKey:@"channel_id"];
                            NSString* messageId = [d objectForKey:@"id"];
                            
                            //Check if a channel is currently being viewed
                            //and if so, if that channel is the same the message was sent in
                            if(weakSelf.selectedChannel != nil && [channelIdOfMessage isEqualToString:weakSelf.selectedChannel.snowflake]) {
                                
								//Send notification with the new message
								//will be recieved by DCChatViewController
								[NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE CREATE" object:weakSelf userInfo:d];
                                
                                //Update current channel & read state last message
                                [weakSelf.selectedChannel setLastMessageId:messageId];
                                
                                //Ack message since we are currently viewing this channel
                                [weakSelf.selectedChannel ackMessage:messageId];
                            }else{
                                DCChannel* channelOfMessage = [weakSelf.channels objectForKey:channelIdOfMessage];
                                channelOfMessage.lastMessageId = messageId;
                                
                                [channelOfMessage checkIfRead];
								[NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE ACK" object:weakSelf];
                            }
                        });
					}
                    
                    if([t isEqualToString:@"MESSAGE_UPDATE"]){
						dispatch_async(dispatch_get_main_queue(), ^{
                            NSString* channelIdOfMessage = [d objectForKey:@"channel_id"];
                            NSString* messageId = [d objectForKey:@"id"];
                            
                            //Check if a channel is currently being viewed
                            //and if so, if that channel is the same the message was sent in
                            if(weakSelf.selectedChannel != nil && [channelIdOfMessage isEqualToString:weakSelf.selectedChannel.snowflake]) {
                                
								//Send notification with the new message
								//will be recieved by DCChatViewController
								[NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE EDIT" object:weakSelf userInfo:d];
                                
                                //Update current channel & read state last message
                                [weakSelf.selectedChannel setLastMessageId:messageId];
                                
                                //Ack message since we are currently viewing this channel
                                [weakSelf.selectedChannel ackMessage:messageId];
                            }
                        });
					}
					
					if([t isEqualToString:@"MESSAGE_ACK"])
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE ACK" object:weakSelf];
                        });
					
					if([t isEqualToString:@"MESSAGE_DELETE"])
						dispatch_async(dispatch_get_main_queue(), ^{
							//Send notification with the new message
							//will be recieved by DCChatViewController
							[NSNotificationCenter.defaultCenter postNotificationName:@"MESSAGE DELETE" object:weakSelf userInfo:d];
						});
                    
					
					if([t isEqualToString:@"GUILD_CREATE"])
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [weakSelf.guilds addObject:[DCTools convertJsonGuild:d]];
                        });
				}
					break;
					
					
				case 11: {
					NSLog(@"Got heartbeat response");
					weakSelf.didRecieveHeartbeatResponse = true;
                    if ([UIApplication sharedApplication].networkActivityIndicatorVisible > 0)
                        [UIApplication sharedApplication].networkActivityIndicatorVisible--;
                    else if ([UIApplication sharedApplication].networkActivityIndicatorVisible < 0)
                        [UIApplication sharedApplication].networkActivityIndicatorVisible = 0;
				}
					break;
					
				case 9:
					dispatch_async(dispatch_get_main_queue(), ^{
						[weakSelf reconnect];
					});
					break;
			}
		}];
		
		[weakSelf.websocket open];
	}
}


- (void)sendResume{
	[self showNonIntrusiveNotificationWithTitle:@"Resuming"];
	self.didTryResume = true;
	self.shouldResume = true;
	[self startCommunicator];
}



- (void)reconnect{
	
	NSLog(@"Identify cooldown %s", self.identifyCooldown ? "true" : "false");
	
	//Begin new session
	[self.websocket close];
	
	//If an identify cooldown is in effect, wait for the time needed until sending another IDENTIFY
	//if not, send immediately
	if(self.identifyCooldown){
		NSLog(@"No cooldown in effect. Authenticating...");
		[self.alertView setTitle:@"Authenticating"];
		[self startCommunicator];
	}else{
		double timeRemaining = self.cooldownTimer.fireDate.timeIntervalSinceNow;
		NSLog(@"Cooldown in effect. Time left %f", timeRemaining);
		//[self.notificationView setTitle:@"Waiting for auth cooldown..."];
        [self showNonIntrusiveNotificationWithTitle:@"Waiting for auth cooldown..."];
		[self performSelector:@selector(startCommunicator) withObject:nil afterDelay:timeRemaining + 1];
	}
	
	self.identifyCooldown = false;
}


- (void)sendHeartbeat:(NSTimer *)timer{
	//Check that we've recieved a response since the last heartbeat
	if(self.didRecieveHeartbeatResponse){
		[NSTimer scheduledTimerWithTimeInterval:8 target:self selector:@selector(checkForRecievedHeartbeat:) userInfo:nil repeats:NO];
		[self sendJSON:@{ @"op": @1, @"d": @(self.sequenceNumber)}];
		NSLog(@"Sent heartbeat");
		[self setDidRecieveHeartbeatResponse:false];
        self.didTryResume = false;
	} else if (self.didTryResume) {
        NSLog(@"Did not get resume, trying reconnect instead with sequence %i %@", self.sequenceNumber, self.sessionId);
        [self reconnect];
        self.didTryResume = false;
    } else {
		//If we didnt get a response in between heartbeats, we've disconnected from the websocket
		//send a RESUME to reconnect
		NSLog(@"Did not get heartbeat response, sending RESUME with sequence %i %@ (sendHeartbeat)", self.sequenceNumber, self.sessionId);
		[self sendResume];
	}
}

- (void)checkForRecievedHeartbeat:(NSTimer *)timer{
	if(!self.didRecieveHeartbeatResponse){
		NSLog(@"Did not get heartbeat response, sending RESUME with sequence %i %@ (checkForRecievedHeartbeat)", self.sequenceNumber, self.sessionId);
		[self sendResume];
	}
}

//Once the 5 second identify cooldown is over
- (void)refreshIdentifyCooldown:(NSTimer *)timer{
	self.identifyCooldown = true;
	NSLog(@"Authentication cooldown ended");
}

- (void)sendJSON:(NSDictionary*)dictionary{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *writeError = nil;
        
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:&writeError];
        
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        [self.websocket sendText:jsonString];
    });
}

@end