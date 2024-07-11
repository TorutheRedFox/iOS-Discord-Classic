//
//  DCImageViewController.m
//  Discord Classic
//
//  Created by Trevir on 11/17/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import "DCImageViewController.h"

@interface DCImageViewController ()

@end

@implementation DCImageViewController

- (void)viewDidLoad{
	[super viewDidLoad];
    [self.share setBackgroundImage:[UIImage imageNamed:@"BarButton"] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [self.share setBackgroundImage:[UIImage imageNamed:@"BarButtonPressed"] forState:UIControlStateSelected barMetrics:UIBarMetricsDefault];
    
}

- (void)viewDidUnload {
	[self setImageView:nil];
    [self setScrollView:nil];
	[super viewDidUnload];
}

-(IBAction)presentShareSheet:(id)sender{
	//Show share sheet with appropriate options
	NSArray *itemsToShare = @[self.imageView.image];
	UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:itemsToShare applicationActivities:nil];
	[activityVC viewWillAppear:YES];
    [self presentViewController:activityVC animated:YES completion:nil];
    [activityVC viewWillAppear:YES];
}

-(UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView{return self.imageView;}
@end
