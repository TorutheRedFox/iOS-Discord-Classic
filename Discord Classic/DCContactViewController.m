//
//  DCContactViewController.m
//  Discord Classic
//
//  Created by bag.xml on 27/01/24.
//  Copyright (c) 2024 Julian Triveri. All rights reserved.
//

#import "DCContactViewController.h"

@interface DCContactViewController ()

@property DCUser* user;
@property (weak, nonatomic) IBOutlet UIImageView *profileImageView;
@property (weak, nonatomic) IBOutlet UILabel *nameLabel;
@property (weak, nonatomic) IBOutlet UILabel *handleLable;
@property (weak, nonatomic) IBOutlet UITextView *descriptionBox;
@end

@implementation DCContactViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

-(void)setSelectedUser:(DCUser*)user{
    self.view = self.view;
    self.navigationItem.title = user.globalName;
    self.nameLabel.text = user.globalName;
    self.handleLable.text = user.username;
    self.profileImageView.image = user.profileImage;
    self.user = user;
    self.descriptionBox.text = user.description;
}

@end
