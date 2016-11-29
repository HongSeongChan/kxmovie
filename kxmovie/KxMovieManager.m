//
//  KxMovieManager.m
//  kxmovie
//
//  Created by insoocop on 2016. 8. 24..
//  Copyright © 2016 insoocop. All rights reserved.
//

#import "KxMovieManager.h"

@implementation KxMovieManager

+ (id)sharedInstance
{
    static KxMovieManager *__instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __instance = [[KxMovieManager alloc] init];
    });
    return __instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.recordFileName = @"temp.mp4";
    }
    
    return self;
}

- (void)setCamType:(KxMovieCamType)camType
          playType:(KxMoviePlayType)playType
{
    self.camType = camType;
    self.playType = playType;
}

@end
