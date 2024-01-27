//
//  DCWelcomeViewController.h
//  Discord Classic
//
//  Created by Trevir on 11/22/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DCWelcomeViewController : UIViewController

@property (weak, nonatomic) IBOutlet UITextField *tokenTextField;
@property (weak, nonatomic) IBOutlet UIButton *loginButton;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *loginIndicator;

@property bool authenticated;

@end
