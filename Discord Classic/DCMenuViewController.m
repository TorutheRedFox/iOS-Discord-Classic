//
//  DCMenuViewController.m
//  Discord Classic
//
//  Created by bag.xml on 27/01/24.
//  Copyright (c) 2024 Julian Triveri. All rights reserved.
//

#import "DCMenuViewController.h"

@interface DCMenuViewController ()


@end

@implementation DCMenuViewController

- (void)viewDidLoad{
	[super viewDidLoad];
	
    
	//Go to settings if no token is set
	if(!DCServerCommunicator.sharedInstance.token.length)
		[self performSegueWithIdentifier:@"to Tokenpage" sender:self];
	
    //NOTIF OBSERVERS
    
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleReady) name:@"READY" object:nil];
	
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleReady) name:@"MESSAGE ACK" object:nil];
	
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleMessageAck) name:@"MESSAGE ACK" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleMessageAck) name:@"RELOAD CHANNEL LIST" object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleReady) name:@"RELOAD GUILD LIST" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleMessageAck) name:@"MESSAGE ACK" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleMessageAck) name:@"RELOAD CHANNEL LIST" object:nil];
    //pns observers
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNotificationTap:) name:@"NavigateToChannel" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(exitedChatController) name:@"ChannelSelectionCleared" object:nil];
    //NOTIF OBSERVERS END
    
    //TOOLBAR IMAGE LOGIC
    UIImage *toolbarBGImage = [UIImage imageNamed:@"ToolbarBG"];
    
    [self.toolbar setBackgroundImage:toolbarBGImage forToolbarPosition:UIToolbarPositionAny barMetrics:UIBarMetricsDefault];
    //toolbar image logic end
}


//block that handles what the app does if you open it via a push ntoification


- (void)handleNotificationTap:(NSNotification *)notification {
    //NSLog(@"HANDLE NOTIFICATION TAP CALLED");
    NSString *channelId = notification.userInfo[@"channelId"];
    if (channelId) {
        //NSLog(@"Navigating to channel with ID: %@", channelId);
        [self navigateToChannelWithId:channelId];
    }
}

-(void)exitedChatController {
    //NSLog(@"EXITING CHAT VIEW");
    self.selectedChannel = nil;
}

- (void)navigateToChannelWithId:(NSString *)channelId {
    for (DCGuild *guild in DCServerCommunicator.sharedInstance.guilds) {
        for (DCChannel *channel in guild.channels) {
            if ([channel.snowflake isEqualToString:channelId]) {
                //NSLog(@"channel id: %@", channelId);
                if (self.selectedChannel && [self.selectedChannel.snowflake isEqualToString:channelId]) {
                    //NSLog(@"ok");
                    return;
                }
                self.selectedGuild = guild;
                self.selectedChannel = channel;
                DCServerCommunicator.sharedInstance.selectedChannel = channel;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self performSegueWithIdentifier:@"guilds to chat" sender:self];
                });
                return;
            }
        }
    }
}
//end of block

//reload
/*- (void)handleReady {
    [self.guildTableView reloadData];
    [self.channelTableView reloadData];
}*/

- (void)handleReady {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.guildTableView reloadData];
        [self.channelTableView reloadData];
        
        if(VERSION_MIN(@"6.0") && !self.refreshControl){
            self.refreshControl = UIRefreshControl.new;
            self.reloadControl = UIRefreshControl.new;
            
            self.reloadControl.attributedTitle = [[NSAttributedString alloc] initWithString:@"Reload"];
            self.refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:@"Reauthenticate"];
            
            [self.guildTableView addSubview:self.refreshControl];
            [self.channelTableView addSubview:self.reloadControl];
            
            [self.reloadControl addTarget:self action:@selector(reloadTable) forControlEvents:UIControlEventValueChanged];
            [self.refreshControl addTarget:self action:@selector(reconnect) forControlEvents:UIControlEventValueChanged];
        }
    });
}

- (void)reloadTable {
    [self.channelTableView reloadData];
    if (VERSION_MIN(@"6.0"))
        [self.reloadControl endRefreshing];
}

- (void)reconnect {
	[DCServerCommunicator.sharedInstance reconnect];
    if (VERSION_MIN(@"6.0"))
        [self.refreshControl endRefreshing];
}

//reload end
//misc
- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
}

- (void)handleMessageAck {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.channelTableView reloadData];
    });
}

//idk what to do with this ngl
-(void)viewWillAppear:(BOOL)animated{
    if (self.selectedGuild) {
        [self.channelTableView reloadData];
        [DCServerCommunicator.sharedInstance setSelectedChannel:nil];
        [self.channelTableView reloadData];
        if ([self.navigationItem.title isEqualToString:@"Direct Messages"]) {
            NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"lastMessageId" ascending:NO selector:@selector(localizedStandardCompare:)];
            [self.selectedGuild.channels sortUsingDescriptors:@[sortDescriptor]];
            
            [self.channelTableView reloadData];
        }
    } else {
        [self.navigationItem setTitle:@"Discord"];
    }
}

//misc end
- (IBAction)moreInfo:(id)sender {
    UIActionSheet *messageActionSheet = [[UIActionSheet alloc] initWithTitle:self.selectedGuild.name delegate:self cancelButtonTitle:@"Okay" destructiveButtonTitle:nil otherButtonTitles:nil, nil];
    [messageActionSheet setDelegate:self];
    [messageActionSheet showInView:self.view];
}
//BUTTON ACTIONS

//BUTTON ACTIONS END
//TABLEVIEW(S)
/*
- (void)initiatebannersequence {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //NSLog(@"%@ rfuieopkrghiurfeogrtihgurojg", self.selectedGuild.snowflake);
        NSString *mediaURL = @"https://cdn.discordapp.com/banners/624739448927682611/5278d848560205e7a90172339a315b8e.png?size=480";
        NSURL *mediaImageUrl = [NSURL URLWithString:mediaURL];
        NSData *mediaData = [NSData dataWithContentsOfURL:mediaImageUrl];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.guildBanner.image = [UIImage imageWithData:mediaData];
        });
    });
}
*/
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	
	if(tableView == self.guildTableView){
		self.selectedGuild = [DCServerCommunicator.sharedInstance.guilds objectAtIndex:indexPath.row];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self.navigationItem setTitle:self.selectedGuild.name];
        self.guildLabel.text = self.selectedGuild.name;
		[self.channelTableView reloadData];
	}
    
    if(tableView == self.channelTableView){
        self.selectedChannel = (DCChannel*)[self.selectedGuild.channels objectAtIndex:indexPath.row];
        DCServerCommunicator.sharedInstance.selectedChannel = [self.selectedGuild.channels objectAtIndex:indexPath.row];
        
        //Mark channel messages as read and refresh the channel object accordingly
        [DCServerCommunicator.sharedInstance.selectedChannel ackMessage:DCServerCommunicator.sharedInstance.selectedChannel.lastMessageId];
        [DCServerCommunicator.sharedInstance.selectedChannel checkIfRead];
        
        //Remove the blue indicator since the channel has been read
        [[self.channelTableView cellForRowAtIndexPath:indexPath] setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self performSegueWithIdentifier:@"guilds to chat" sender:self];
        
        [tableView cellForRowAtIndexPath:indexPath].accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    
    if (tableView == self.guildTableView) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"guild"];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"guild"];
        }
        
        DCServerCommunicator.sharedInstance.guilds = [[DCServerCommunicator.sharedInstance.guilds sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            NSString *first = [(DCGuild *)a name];
            NSString *second = [(DCGuild *)b name];
            if ([first compare:@"Direct Messages"] == 0) return false; // DMs at the top
            return [first compare:second];
        }] mutableCopy];
        
        DCGuild *guildAtRowIndex = [DCServerCommunicator.sharedInstance.guilds objectAtIndex:indexPath.row];
        
        // Guild name and icon
        cell.textLabel.text = @"";
        [cell.imageView setImage:guildAtRowIndex.icon];
        cell.imageView.frame = CGRectMake(0, 0, 32, 32);
        cell.imageView.layer.cornerRadius = cell.imageView.frame.size.height / 2.0;
        cell.imageView.layer.masksToBounds = YES;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
        cell.imageView.clipsToBounds = YES;
    }
    
    if (tableView == self.channelTableView) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"channel"];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"channel"];
        }
        
        DCChannel *channelAtRowIndex = [self.selectedGuild.channels objectAtIndex:indexPath.row];
        if (channelAtRowIndex.unread) {
            [cell setAccessoryType:UITableViewCellAccessoryDetailDisclosureButton];
        } else {
            [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        }
        
        [cell.textLabel setText:channelAtRowIndex.name];
    }
    
    return cell;
}


- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{
    // make guild icons a fixed size
    if(tableView == self.guildTableView) {
    cell.imageView.frame = CGRectMake(0, 0, 32, 32);
    cell.imageView.layer.cornerRadius = cell.imageView.frame.size.height / 4.0;
    cell.imageView.layer.masksToBounds = YES;
    [cell.imageView setNeedsDisplay];
    [cell layoutIfNeeded];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	
	if(tableView == self.guildTableView)
    {return DCServerCommunicator.sharedInstance.guilds.count;}
	
    if(tableView == self.channelTableView)
        return self.selectedGuild.channels.count;
    
    return 0;
}

//SEGUE
- (void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender{
    if([segue.destinationViewController class] == [DCChatViewController class]){
        if ([segue.identifier isEqualToString:@"guilds to chat"]){
            DCChatViewController *chatViewController = [segue destinationViewController];
            
            if ([chatViewController isKindOfClass:DCChatViewController.class]){
                
                //Initialize messages
                chatViewController.messages = NSMutableArray.new;
                NSString* formattedChannelName;
                if(DCServerCommunicator.sharedInstance.selectedChannel.type == 0)
                    formattedChannelName = [@"#" stringByAppendingString:DCServerCommunicator.sharedInstance.selectedChannel.name];
                else
                    formattedChannelName = DCServerCommunicator.sharedInstance.selectedChannel.name;
                [chatViewController.navigationItem setTitle:formattedChannelName];
                [chatViewController getMessages:50 beforeMessage:nil];
                [chatViewController setViewingPresentTime:true];
            }
        }
        
    }
}
//SEGUE END
@end
