//
//  KxMoviePlayerView.h
//  kxmovie
//
//  Created by insoocop on 2016. 8. 24..
//  Copyright © 2016 insoocop. All rights reserved.
//
//  https://github.com/kolyvan/kxmovie
//  this file is part of KxMovie
//  KxMovie is licenced under the LGPL v3, see lgpl-3.0.txt

#import <UIKit/UIKit.h>
#import "KxMovieDecoder.h"
#import "KxAudioManager.h"
#import "KxMovieGLView.h"
#import "KxLogger.h"

@protocol KxMoviePlayerViewDelegate <NSObject>

@optional
- (void)playerDidStart;
- (void)playerDidStartWithTag:(NSInteger)tag;
- (void)playerDidStop;

- (void)networkFailCount:(NSInteger)count tag:(NSInteger)tag;
- (void)maxValue:(NSInteger)maxValue currentValue:(NSInteger)currentValue;
- (void)decoderError:(NSError *)error;
- (void)playerRenderWidth:(NSUInteger)width height:(NSUInteger)height;
- (void)playerStart;
@end


@interface KxMoviePlayerView : UIView

- (instancetype) initWithFrame: (CGRect) frame
                   contentPath: (NSString *) path
                    parameters: (NSDictionary *) parameters;
- (void) videoPath: (NSString *) path;
@property (nonatomic, assign) id<KxMoviePlayerViewDelegate>delegate;

- (UIView *) getGlView;
@property (nonatomic, strong) KxMovieDecoder *decoder;


- (void) didReceiveMemoryWarning;    //didReceiveMemoryWarning에 추가
- (void) viewDidAppear;              //viewDidAppear에 추가
- (void) viewWillDisappear;          //viewWillDisappear에 추가
- (void) viewDidAppearPlay DEPRECATED_MSG_ATTRIBUTE("Use viewDidAppear instead.");
- (void) viewWillDisappearPlay DEPRECATED_MSG_ATTRIBUTE("Use viewWillDisappear instead.");

- (void) clearMemory;
- (void) reloadSubView;

- (void) audioMute: (BOOL) mute;        //뮤트 여부 세팅
@property (readonly) BOOL isAudioMute;  //뮤트 여부

- (void) play;       //플레이
- (void) pause;      //멈추기
- (void) stop;       //종료
- (BOOL) isPlaying;
- (void) playEnd;
@property (readonly) BOOL playing;              //플레이 여부
@property (nonatomic,assign) BOOL isSelected;   //선택 여부

- (void) seekTime: (CGFloat) seconds;      //검색
- (void) progressDidChange: (id) sender;
- (CGFloat) duration;
- (CGFloat) position;
- (CGFloat) isEOF;
- (void) setMoviePosition: (CGFloat) position;

- (void) updateFrame;   //Playing 상태가 아닐때 현재 프레임을 출력함.

- (UIImage *) getCurrentImage;   //캡춰 이미지 get

- (void) recordStart;
- (void) recordStop;
- (BOOL) isRecord;
- (CGSize) getDecoderFrameSize;

@end
