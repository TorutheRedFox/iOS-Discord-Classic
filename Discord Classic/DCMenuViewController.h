//
//  DCMenuViewController.h
//  Discord Classic
//
//  Created by bag.xml on 27/01/24.
//  Copyright (c) 2024 Julian Triveri. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCGuild.h"
#import "DCChannel.h"
#import "DCChatViewController.h"
#import "DCChatViewController.h"
#import "DCServerCommunicator.h"
#import "DCTools.h"
#import "DCUser.h"

#define VERSION_MIN(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

@interface DCMenuViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (weak, nonatomic) IBOutlet UITableView *guildTableView;
@property (weak, nonatomic) IBOutlet UITableView *channelTableView;
@property DCGuild *selectedGuild;
@property DCChannel *selectedChannel;
@property UIRefreshControl *refreshControl;
@property UIRefreshControl *reloadControl;
@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property (weak, nonatomic) IBOutlet UILabel *guildLabel;
@property (weak, nonatomic) IBOutlet UIImageView *guildBanner;

@property NSOperationQueue* serverIconImageQueue;

@end
