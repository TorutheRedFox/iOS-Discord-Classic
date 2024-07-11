//
//  DCContactViewController.h
//  Discord Classic
//
//  Created by bag.xml on 27/01/24.
//  Copyright (c) 2024 Julian Triveri. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DCUser.h"

@interface DCContactViewController : UITableViewController

-(void)setSelectedUser:(DCUser*)user;

@end
