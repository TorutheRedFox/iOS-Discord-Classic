//
//  DCWelcomeController.m
//  Discord Classic
//
//  Created by bag.xml on 27/01/24.
//  Copyright (c) 2024 Julian Triveri. All rights reserved.
//

#import "DCWelcomeController.h"
#import "DCServerCommunicator.h"
@interface DCWelcomeController ()

@end

@implementation DCWelcomeController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    self.authenticated = false;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	self.navigationItem.hidesBackButton = YES;
    
    NSString *token = [NSUserDefaults.standardUserDefaults objectForKey:@"token"];
    
    if(token){
        self.tokenTextField.text = token;
    }else{
        self.tokenTextField.text = UIPasteboard.generalPasteboard.string;
    }
    
}

- (IBAction)loginButtonWasClicked {
    if(self.tokenTextField.text.length == 0) {
        [self showAlertWithTitle:@"Nothing..." message:@"Make sure to properly type in your token."];
    } else {
        [self.loginIndicator startAnimating];
        [self.loginIndicator setHidden:false];
        [NSUserDefaults.standardUserDefaults setObject:self.tokenTextField.text forKey:@"token"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        //Save the entered values and reauthenticate if the token has been changed
        if(![DCServerCommunicator.sharedInstance.token isEqual:[NSUserDefaults.standardUserDefaults valueForKey:@"token"]]){
            DCServerCommunicator.sharedInstance.token = self.tokenTextField.text;
            [DCServerCommunicator.sharedInstance reconnect];
            [self didLogin];
        }
        [self.loginButton setHidden:true];
    }
}

- (void)didLogin {
    [self performSegueWithIdentifier:@"login to guilds" sender:self];
    self.authenticated = true;
    // user shouldn't be able to go back to this screen once logged in
    NSMutableArray *navigationArray = [[NSMutableArray alloc] initWithArray: self.navigationController.viewControllers];
    [navigationArray removeObjectAtIndex:0];
    self.navigationController.viewControllers = navigationArray;
    
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



- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alertView show];
}
@end

