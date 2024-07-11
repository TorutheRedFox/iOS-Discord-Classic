//
//  DCUser.m
//  Discord Classic
//
//  Created by Trevir on 11/17/18.
//  Copyright (c) 2018 Julian Triveri. All rights reserved.
//

#import "DCUser.h"

@implementation DCUser

+ (NSArray *)defaultAvatars
{
    static NSArray *_defaultAvatars;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _defaultAvatars = @[[UIImage imageNamed:@"DefaultAvatar0"],
                            [UIImage imageNamed:@"DefaultAvatar1"],
                            [UIImage imageNamed:@"DefaultAvatar2"],
                            [UIImage imageNamed:@"DefaultAvatar3"],
                            [UIImage imageNamed:@"DefaultAvatar4"],
                            [UIImage imageNamed:@"DefaultAvatar5"],
                            ];
    });
    return _defaultAvatars;
}

-(NSString *)description{
	return [NSString stringWithFormat:@"[User] Snowflake: %@, Username: %@, Display name %@", self.snowflake, self.username, self.globalName];
}
@end
