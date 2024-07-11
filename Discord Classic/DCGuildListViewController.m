//
//  DCGuildViewController.m
//  Discord Classic
//
//  Created by Julian Triveri on 3/4/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import "DCGuildListViewController.h"
#import "DCChannelListViewController.h"
#import "DCServerCommunicator.h"
#import "DCGuild.h"
#import "DCTools.h"

@implementation DCGuildListViewController

- (void)viewDidLoad{
	[super viewDidLoad];
	
	//Go to settings if no token is set
	if(!DCServerCommunicator.sharedInstance.token.length)
		[self performSegueWithIdentifier:@"to Settings" sender:self];
    
    self.navigationItem.hidesBackButton = YES;
    
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleReady) name:@"READY" object:nil];
	
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleReady) name:@"MESSAGE ACK" object:nil];
	
	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleReady) name:@"RELOAD GUILD LIST" object:nil];
}


- (void)handleReady {
	//Refresh tableView data on READY notification
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
        
        if(VERSION_MIN(@"6.0") && !self.refreshControl){
            self.refreshControl = UIRefreshControl.new;
            self.refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:@"Reauthenticate"];
            
            [self.tableView addSubview:self.refreshControl];
            
            [self.refreshControl addTarget:self action:@selector(reconnect) forControlEvents:UIControlEventValueChanged];
        }
    });
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Guild Cell"];
	
    //Sorts guilds alphabetically, Note that this code may not yield the best results, and should be modified in the future. It can crash the app sometimes.
	DCServerCommunicator.sharedInstance.guilds = [[DCServerCommunicator.sharedInstance.guilds sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
		NSString *first = [(DCGuild*)a name];
		NSString *second = [(DCGuild*)b name];
		if([first compare:@"Direct Messages"] == 0) return false; // DMs at the top
		return [first compare:second];
	}] mutableCopy];

	DCGuild* guildAtRowIndex = [DCServerCommunicator.sharedInstance.guilds objectAtIndex:indexPath.row];
    
	//Show blue indicator if guild has any unread messages
	if(guildAtRowIndex.unread)
		[cell setAccessoryType:UITableViewCellAccessoryDetailDisclosureButton];
	else
		[cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
	
	//Guild name and icon
	[cell.textLabel setText:guildAtRowIndex.name];
	[cell.imageView setImage:guildAtRowIndex.icon];
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.clipsToBounds = YES;
    
	return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{
    // make guild icons a fixed size
    cell.imageView.frame = CGRectMake(0, 0, 40, 40);
    cell.imageView.layer.cornerRadius = cell.imageView.frame.size.height / 2.0;
    cell.imageView.layer.masksToBounds = YES;
    [cell.imageView setNeedsDisplay];
    [cell layoutIfNeeded];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
	
	if([DCServerCommunicator.sharedInstance.guilds objectAtIndex:indexPath.row] != DCServerCommunicator.sharedInstance.selectedGuild){
		//Clear the loaded users array for lazy memory management. This will be fleshed out more later
		DCServerCommunicator.sharedInstance.loadedUsers = NSMutableDictionary.new;
		//Assign the selected guild
		DCServerCommunicator.sharedInstance.selectedGuild = [DCServerCommunicator.sharedInstance.guilds objectAtIndex:indexPath.row];
	}
	
	//Transition to channel list 
	[self performSegueWithIdentifier:@"Guilds to Channels" sender:self];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender{
	if ([segue.identifier isEqualToString:@"Guilds to Channels"]){
		
		DCChannelListViewController *channelListViewController = [segue destinationViewController];
		
		if ([channelListViewController isKindOfClass:DCChannelListViewController.class]) {
			//Assign selected guild for the channel list we are transitioning to. 
			channelListViewController.selectedGuild = DCServerCommunicator.sharedInstance.selectedGuild;
            
            // sort DMs by most recent
            if ([channelListViewController.navigationItem.title isEqualToString:@"Direct Messages"]) {
                // Sort the DMs list by most recent...
                NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"lastMessageId" ascending:NO selector:@selector(localizedStandardCompare:)];
                [channelListViewController.selectedGuild.channels sortUsingDescriptors:@[sortDescriptor]];
            }
        }
	}
}

- (IBAction)joinGuildPrompt:(id)sender{
	UIAlertView *joinPrompt = [[UIAlertView alloc] initWithTitle:@"Enter invite code"
																											 message:nil
																											delegate:self
																						 cancelButtonTitle:@"Cancel"
																						 otherButtonTitles:@"Join", nil];
	
	[joinPrompt setAlertViewStyle:UIAlertViewStylePlainTextInput];
	[joinPrompt setDelegate:self];
	[joinPrompt show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
	if([[alertView buttonTitleAtIndex:buttonIndex] isEqualToString:@"Join"])
		[DCTools joinGuild:[alertView textFieldAtIndex:0].text];
}

- (void)reconnect {
	[DCServerCommunicator.sharedInstance reconnect];
    if (VERSION_MIN(@"6.0"))
        [self.refreshControl endRefreshing];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 1;}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return DCServerCommunicator.sharedInstance.guilds.count;}

@end