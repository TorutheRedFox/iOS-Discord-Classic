//
//  DCSettingsViewController.m
//  Discord Classic
//
//  Created by Trevir on 3/18/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import "DCSettingsViewController.h"
#import "DCServerCommunicator.h"
#import "DCTools.h"

@implementation DCSettingsViewController

- (void)viewDidLoad{
	[super viewDidLoad];
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
	if(indexPath.row == 1 && indexPath.section == 1){
		[DCTools joinGuild:@"A93uJh3"];
		[self performSegueWithIdentifier:@"Settings to Test Channel" sender:self];
	}
}
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.textLabel.textColor = [UIColor colorWithRed:116.0/255.0 green:116.0/255.0 blue:116.0/255.0 alpha:1.0];
    header.textLabel.shadowOffset = CGSizeMake(0, 0);
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
    footer.textLabel.textColor = [UIColor colorWithRed:116.0/255.0 green:116.0/255.0 blue:116.0/255.0 alpha:1.0];
    footer.textLabel.shadowOffset = CGSizeMake(0, 0);
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender{
	if ([segue.identifier isEqualToString:@"Settings to Test Channel"]){
		DCChatViewController *chatViewController = [segue destinationViewController];
		
		if ([chatViewController isKindOfClass:DCChatViewController.class]){
			
			DCServerCommunicator.sharedInstance.selectedChannel = [DCServerCommunicator.sharedInstance.channels valueForKey:@"1162446567488364627"];
			
			//Initialize messages
			chatViewController.messages = NSMutableArray.new;
			
			[chatViewController.navigationItem setTitle:@"Discord Classic #general"];
			
			//Populate the message view with the last 50 messages
            //dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                [chatViewController getMessages:50 beforeMessage:nil];
            //});
			
			//Chat view is watching the present conversation (auto scroll with new messages)
			[chatViewController setViewingPresentTime:YES];
		}
	}
}

@end