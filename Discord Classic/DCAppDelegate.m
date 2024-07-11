//
//  DCAppDelegate.m
//  Discord Classic
//
//  Created by Julian Triveri on 3/2/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import "DCAppDelegate.h"
#import "DCServerCommunicator.h"

@interface DCAppDelegate()
@property bool shouldReload;
@end

@implementation DCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window.backgroundColor = [UIColor clearColor];
    self.window.opaque = NO;
    self.shouldReload = false;
    
    [UINavigationBar.appearance setBackgroundImage:[UIImage imageNamed:@"TbarBG"] forBarMetrics:UIBarMetricsDefault];
    NSURLCache *urlCache = [[NSURLCache alloc] initWithMemoryCapacity:1024*1024*8  // 8MB mem cache
                                                         diskCapacity:1024*1024*60 // 60MB disk cache
                                                             diskPath:nil];
    [NSURLCache setSharedURLCache:urlCache];
    application.applicationIconBadgeNumber = 0;
    
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("dis.cord.Discord.badgeReset"), NULL, NULL, true);
    
    if (launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]) {
        NSDictionary *notification = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
        NSDictionary *aps = notification[@"aps"];
        NSString *channelId = aps[@"channelId"]; // Adjusted to reflect your payload structure
        NSLog(@"Channel id: %@", channelId);
        if (channelId) {
            NSLog(@"App launched with notification, channelId: %@", channelId);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"NavigateToChannel" object:nil userInfo:@{@"channelId": channelId}];
            });
        }
    }
    
    if (DCServerCommunicator.sharedInstance.token.length)
        [DCServerCommunicator.sharedInstance startCommunicator];
    
    return YES;
}


- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    NSLog(@"RECEIVED REMOTE NOTIFICATION");
    
    NSDictionary *aps = userInfo[@"aps"];
    NSString *channelId = aps[@"channelId"];
    NSLog(@"Received notification with Channel id: %@", channelId);
    
    if (channelId) {
        UIApplicationState state = [application applicationState];
        if (state == UIApplicationStateInactive || state == UIApplicationStateBackground) {
            // App was in the background or not running, meaning the user tapped the notification
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"NavigateToChannel" object:nil userInfo:@{@"channelId": channelId}];
            });
        } else {
            NSLog(@"FUCK YOU LJB I HATE YOU");
        }
    }
}

- (void)applicationWillResignActive:(UIApplication *)application{
	NSLog(@"Will resign active");
}


- (void)applicationDidEnterBackground:(UIApplication *)application{
	NSLog(@"Did enter background");
	self.shouldReload = DCServerCommunicator.sharedInstance.didAuthenticate;
}


- (void)applicationWillEnterForeground:(UIApplication *)application{
	NSLog(@"Will enter foreground");
}


- (void)applicationDidBecomeActive:(UIApplication *)application{
	NSLog(@"Did become active");
	if(self.shouldReload){
		[DCServerCommunicator.sharedInstance sendResume];
	}
}


- (void)applicationWillTerminate:(UIApplication *)application{
	NSLog(@"Will terminate");
}

@end
