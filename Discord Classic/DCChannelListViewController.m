//
//  DCChannelViewController.m
//  Discord Classic
//
//  Created by Julian Triveri on 3/5/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import "DCChannelListViewController.h"
#import "DCCInfoViewController.h"
#import "DCChatViewController.h"
#import "DCServerCommunicator.h"
#import "DCGuild.h"
#import "DCChannel.h"
#import "TRMalleableFrameView.h"

@interface DCChannelListViewController ()
@property int selectedChannelIndex;
@property DCChannel* selectedChannel;
@end

@implementation DCChannelListViewController

- (void)viewDidLoad{
	[super viewDidLoad];
	
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleMessageAck) name:@"MESSAGE ACK" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleMessageAck) name:@"RELOAD CHANNEL LIST" object:nil];
}


-(void)viewWillAppear:(BOOL)animated{
	[self.navigationItem setTitle:self.selectedGuild.name];
    [self.tableView reloadData];
	[DCServerCommunicator.sharedInstance setSelectedChannel:nil];
    if ([self.navigationItem.title isEqualToString:@"Direct Messages"]) {
        // Sort the DMs list by most recent...
        NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"lastMessageId" ascending:NO selector:@selector(localizedStandardCompare:)];
        [self.selectedGuild.channels sortUsingDescriptors:@[sortDescriptor]];
        [self.tableView reloadData];
    }
}


- (void)handleMessageAck {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Channel Cell"];
	
	//Show blue indicator if channel contains any unread messages
	DCChannel* channelAtRowIndex = [self.selectedGuild.channels objectAtIndex:indexPath.row];
	if(channelAtRowIndex.unread)
		[cell setAccessoryType:UITableViewCellAccessoryDetailDisclosureButton];
	else
		[cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
    
	//Channel name
	[cell.textLabel setText:channelAtRowIndex.name];
    
    if (channelAtRowIndex.icon != nil && [channelAtRowIndex.icon class] == [UIImage class]) {
        [cell.imageView setImage:channelAtRowIndex.icon];
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
        cell.imageView.clipsToBounds = YES;
        
        cell.imageView.frame = CGRectMake(0, 0, 32, 32);
        cell.imageView.layer.cornerRadius = cell.imageView.frame.size.height / 2.0;
        cell.imageView.layer.masksToBounds = YES;
        [cell.imageView setNeedsDisplay];
        [cell layoutIfNeeded];
    }
	
	return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{
    // make guild icons a fixed size
    cell.imageView.frame = CGRectMake(0, 0, 32, 32);
    cell.imageView.layer.cornerRadius = cell.imageView.frame.size.height / 2.0;
    cell.imageView.layer.masksToBounds = YES;
    [cell.imageView setNeedsDisplay];
    [cell layoutIfNeeded];
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
	DCServerCommunicator.sharedInstance.selectedChannel = [self.selectedGuild.channels objectAtIndex:indexPath.row];
	
	//Mark channel messages as read and refresh the channel object accordingly
	[DCServerCommunicator.sharedInstance.selectedChannel ackMessage:DCServerCommunicator.sharedInstance.selectedChannel.lastMessageId];
	[DCServerCommunicator.sharedInstance.selectedChannel checkIfRead];
	
	//Remove the blue indicator since the channel has been read
	[[self.tableView cellForRowAtIndexPath:indexPath] setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
	
	//Transition to chat view
	[self performSegueWithIdentifier:@"Channels to Chat" sender:self];
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender{
	if ([segue.identifier isEqualToString:@"Channels to Chat"]){
		DCChatViewController *chatViewController = [segue destinationViewController];
		
		if ([chatViewController isKindOfClass:DCChatViewController.class]){
			
			//Initialize messages
			chatViewController.messages = NSMutableArray.new;
			
			//Add a '#' if appropriate to the chanel name in the navigation bar
			NSString* formattedChannelName;
			if(DCServerCommunicator.sharedInstance.selectedChannel.type == 0)
				formattedChannelName = [@"#" stringByAppendingString:DCServerCommunicator.sharedInstance.selectedChannel.name];
			else
				formattedChannelName = DCServerCommunicator.sharedInstance.selectedChannel.name;
			[chatViewController.navigationItem setTitle:formattedChannelName];
			
			//Populate the message view with the last 50 messages
            
			[chatViewController getMessages:50 beforeMessage:nil];
			
			//Chat view is watching the present conversation (auto scroll with new messages)
			[chatViewController setViewingPresentTime:true];
		}
	}
	if ([segue.identifier isEqualToString:@"Channels to RightSidebar"]){
		DCCInfoViewController *rightSidebar = [segue destinationViewController];
		
		if ([rightSidebar isKindOfClass:DCChatViewController.class]){
			[rightSidebar.navigationItem setTitle:self.selectedGuild.name];
		}
	}
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 1;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.selectedGuild.channels.count;}
@end
