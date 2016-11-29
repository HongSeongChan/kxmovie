//
//  KxMovieManager.h
//  kxmovie
//
//  Created by insoocop on 2016. 8. 24..
//  Copyright © 2016 insoocop. All rights reserved.
//
//  https://github.com/kolyvan/kxmovie
//  this file is part of KxMovie
//  KxMovie is licenced under the LGPL v3, see lgpl-3.0.txt

#import <Foundation/Foundation.h>

#define KXVIDEO_VIEW_CUSTOM
#define KxManager     [KxMovieManager sharedInstance]

/* Cam type */
typedef NS_ENUM(NSUInteger, KxMovieCamType) {
    KxMovieCamTypeLG = 0,   // LG
    KxMovieCamTypeXiaoyi,   // Xiaoyi
    KxMovieCamTypeHanwha,   // Hanwha
};

/* Play type */
typedef NS_ENUM(NSUInteger, KxMoviePlayType) {
    KxMoviePlayTypePreview = 0, // Preview (Default)
    KxMoviePlayTypeGallery,     // Gallery
};

@interface KxMovieManager : NSObject

+ (id)sharedInstance;

@property (nonatomic, assign) KxMovieCamType camType;   // Cam type
@property (nonatomic, assign) KxMoviePlayType playType; // Play type

// KxMoviePlayerView의 tick 함수 내에서 KxMoviePlayType 타입으로 동작하고 있기 때문에
// 현재 아래 변수는 사용하고 있지 않음.
@property (nonatomic, assign) BOOL tickIntervalTimeNow DEPRECATED_MSG_ATTRIBUTE("Use KxMoviePlayType playType instead."); // (YES)DISPATCH_TIME_NOW, (NO)popTime 계산

- (void)setCamType:(KxMovieCamType)camType
          playType:(KxMoviePlayType)playType;

@property (nonatomic, strong) NSString *recordFileName; // 동영상 저장시 파일 이름

@end
