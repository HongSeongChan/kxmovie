//
//  KxMoviePlayerView.m
//  kxmovie
//
//  Created by insoocop on 2016. 8. 24..
//  Copyright © 2016 insoocop. All rights reserved.
//

#import "KxMoviePlayerView.h"

NSString * const PlayerParameterMinBufferedDuration = @"PlayerParameterMinBufferedDuration";
NSString * const PlayerParameterMaxBufferedDuration = @"PlayerParameterMaxBufferedDuration";
NSString * const PlayerParameterDisableDeinterlacing = @"PlayerParameterDisableDeinterlacing";

static NSMutableDictionary * gHistory;

#define LOCAL_MIN_BUFFERED_DURATION   0.2
#define LOCAL_MAX_BUFFERED_DURATION   0.4
#ifdef KXVIDEO_VIEW_CUSTOM
#define NETWORK_MIN_BUFFERED_DURATION 0.0
#define NETWORK_MAX_BUFFERED_DURATION 2.0
#else //KXVIDEO_VIEW_CUSTOM
#define NETWORK_MIN_BUFFERED_DURATION 2.0
#define NETWORK_MAX_BUFFERED_DURATION 4.0
#endif //KXVIDEO_VIEW_CUSTOM

@interface KxMoviePlayerView () {
    
//    KxMovieDecoder      *_decoder;
    dispatch_queue_t    _dispatchQueue;
    NSMutableArray      *_videoFrames;
    NSMutableArray      *_audioFrames;
    NSData              *_currentAudioFrame;
    NSUInteger          _currentAudioFramePos;
    CGFloat             _moviePosition;
    NSTimeInterval      _tickCorrectionTime;
    NSTimeInterval      _tickCorrectionPosition;
    NSUInteger          _tickCounter;
    BOOL                _fullscreen;
    BOOL                _fitMode;
    BOOL                _restoreIdleTimer;
    BOOL                _interrupted;
    
    KxMovieGLView       *_glView;
    
    UIActivityIndicatorView *_activityIndicatorView;
    
    CGFloat             _bufferedDuration;
    CGFloat             _minBufferedDuration;
    CGFloat             _maxBufferedDuration;
    BOOL                _buffered;
    
    BOOL                _savedIdleTimer;
    
    NSDictionary        *_parameters;

    BOOL 				isRealPlayStart;
    NSTimer 			*networkTimer;
    NSInteger 			networkFailCount;
    
    BOOL 				isPlayingBackground;
}

@property (readwrite) BOOL playing;
@property (readwrite) BOOL decoding;
@property (readwrite, strong) KxArtworkFrame *artworkFrame;
@property (nonatomic, assign) BOOL isStop;

@end


@implementation KxMoviePlayerView
@synthesize delegate,isSelected;

+ (void) initialize
{
    if (!gHistory)
        gHistory = [NSMutableDictionary dictionary];
}

- (instancetype) initWithFrame: (CGRect) frame
                   contentPath: (NSString *) path
                    parameters: (NSDictionary *) parameters
{
    self = [super initWithFrame:frame];
    if (self) {
        //LG캠일 경우 Indicator 출력
        if ([KxManager camType] == KxMovieCamTypeLG) {  //LG캠
            _activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle: UIActivityIndicatorViewStyleWhite];
            _activityIndicatorView.center = self.center;
            _activityIndicatorView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
            [self addSubview:_activityIndicatorView];
            [_activityIndicatorView startAnimating];
        }
        
        [self initWithContentPath:path parameters:parameters];
        
        if (_decoder) {
            [self setupPresentView];
        }
    }
    return self;
}

- (void) initWithContentPath: (NSString *) path
                  parameters: (NSDictionary *) parameters
{
    NSAssert(path.length > 0, @"empty path");
    
    _moviePosition = 0;
    //        self.wantsFullScreenLayout = YES;
    
    _parameters = parameters;
    
    __weak KxMoviePlayerView *weakSelf = self;
    
    KxMovieDecoder *decoder = [[KxMovieDecoder alloc] init];
    
    decoder.interruptCallback = ^BOOL(){
        
        __strong KxMoviePlayerView *strongSelf = weakSelf;
        return strongSelf ? [strongSelf interruptDecoder] : YES;
    };
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        NSError *error = nil;
        [decoder openFile:path error:&error];
        
        __strong KxMoviePlayerView *strongSelf = weakSelf;
        if (strongSelf) {
            
            dispatch_sync(dispatch_get_main_queue(), ^{
                
                [strongSelf setMovieDecoder:decoder withError:error];
            });
        }
    });
}

- (void) videoPath: (NSString *) path
{
    if( _decoder != nil )
        return;
    
    _isStop = NO;
    isRealPlayStart = NO;
    isPlayingBackground = NO;
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    
    //    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
    //        parameters[MovieParameterDisableDeinterlacing] = @(YES);
    
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    [audioManager activateAudioSession];
    
    if(path == nil|| [path isEqualToString:@""])
        return;
    
    _moviePosition = 0;
    //        self.wantsFullScreenLayout = YES;
    
    _parameters = parameters;
    
    __weak KxMoviePlayerView *weakSelf = self;
    
    KxMovieDecoder *decoder = [[KxMovieDecoder alloc] init];
    
    decoder.interruptCallback = ^BOOL(){
        
        __strong KxMoviePlayerView *strongSelf = weakSelf;
        return strongSelf ? [strongSelf interruptDecoder] : YES;
    };
    
    LoggerVideo(1, @"==================== Start Video Stream(Start : %@)=======================", [NSDate date]);
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        NSError *error = nil;
        [decoder openFile:path error:&error];
        
        __strong KxMoviePlayerView *strongSelf = weakSelf;
        if (strongSelf) {
            
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (strongSelf == nil)
                    return;
                
                [strongSelf setMovieDecoder:decoder withError:error];
            });
        }
    });
    
    if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
        [self loadView];
    }
    else { //Preview //KxMoviePlayTypePreview
        //[self loadView];
    }
}

- (void) dealloc
{
#ifdef KXVIDEO_VIEW_CUSTOM
    if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
        [self pause];
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        
        if (_dispatchQueue) {
            // Not needed as of ARC.
            //        dispatch_release(_dispatchQueue);
            _dispatchQueue = NULL;
        }
        
        LoggerStream(1, @"%@ dealloc", self);
    }
    else { //Preview //KxMoviePlayTypePreview
        [self pause];
        
        _interrupted = YES;
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        
        if (_dispatchQueue) {
            // Not needed as of ARC.
            //        dispatch_release(_dispatchQueue);
            _dispatchQueue = NULL;
        }
        
        LoggerStream(1, @"%@ dealloc", self);
        
        _currentAudioFrame = nil;
        _decoder = nil;
        _parameters = nil;
        gHistory = nil;
        
        _videoFrames = nil;
        _audioFrames = nil;
        
        if(networkTimer){
            networkFailCount = 0;
            [networkTimer invalidate];
            networkTimer = nil;
        }
    }
  
#else //KXVIDEO_VIEW_CUSTOM
    [self pause];
    
    if (_dispatchQueue) {
        // Not needed as of ARC.
        //        dispatch_release(_dispatchQueue);
        _dispatchQueue = NULL;
    }

#endif //KXVIDEO_VIEW_CUSTOM
}

- (void) loadView
{
    // LoggerStream(1, @"loadView");

    
    self.isSelected = NO;
//    CGRect bounds = [[UIScreen mainScreen] applicationFrame];
//    bounds.origin.y = 0;
//    [self setFrame:bounds];
    self.backgroundColor = [UIColor blackColor];
    self.tintColor = [UIColor blackColor];


    if (_decoder) {
        
        [self setupPresentView];
        
    } else {

    }
    
    _savedIdleTimer = [[UIApplication sharedApplication] isIdleTimerDisabled];
    
    if (_decoder) {
        
        [self restorePlay];
        
    } else {
        [self stop];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:[UIApplication sharedApplication]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:[UIApplication sharedApplication]];
}

- (void) didReceiveMemoryWarning
{
    if (self.playing) {
        
        [self pause];
        [self freeBufferedFrames];
        
        if (_maxBufferedDuration > 0) {
            
            _minBufferedDuration = _maxBufferedDuration = 0;
            [self play];
            
            LoggerStream(0, @"didReceiveMemoryWarning, disable buffering and continue playing");
            
        } else {
            
            // force ffmpeg to free allocated memory
            [_decoder closeFile];
            [_decoder openFile:nil error:nil];
            
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                        message:NSLocalizedString(@"Out of memory", nil)
                                       delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                              otherButtonTitles:nil] show];
        }
        
    } else {
        
        [self freeBufferedFrames];
        [_decoder closeFile];
        [_decoder openFile:nil error:nil];
    }
}

- (void) viewDidAppear
{
    // LoggerStream(1, @"viewDidAppear")
    
    _savedIdleTimer = [[UIApplication sharedApplication] isIdleTimerDisabled];
    
    if (_decoder) {
        [self restorePlay];
        
    } else {


    }
   
   
    if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillResignActive:)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:[UIApplication sharedApplication]];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:[UIApplication sharedApplication]];
    }
    else { //Preview //KxMoviePlayTypePreview
//        [[NSNotificationCenter defaultCenter] addObserver:self
//                                                 selector:@selector(applicationWillResignActive:)
//                                                     name:UIApplicationWillResignActiveNotification
//                                                   object:[UIApplication sharedApplication]];
//        
//        [[NSNotificationCenter defaultCenter] addObserver:self
//                                                 selector:@selector(applicationDidBecomeActive:)
//                                                     name:UIApplicationDidBecomeActiveNotification
//                                                   object:[UIApplication sharedApplication]];
    }
}

- (void) viewWillDisappear
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
        if(delegate)
            delegate = nil;
        
        if (_decoder) {
            [self pause];
            
            if (_moviePosition == 0 || _decoder.isEOF)
                [gHistory removeObjectForKey:_decoder.path];
            else if (!_decoder.isNetwork)
                [gHistory setValue:[NSNumber numberWithFloat:_moviePosition]
                            forKey:_decoder.path];
        }
        
        //    if (_dispatchQueue) {
        //        // Not needed as of ARC.
        //        //        dispatch_release(_dispatchQueue);
        //        _dispatchQueue = NULL;
        //    }
        
        // 임시로 막음... 해결해야 될 문제...
        //    [self stop];
        
        if (_fullscreen)
            [self fullscreenMode:NO];
        
        [[UIApplication sharedApplication] setIdleTimerDisabled:_savedIdleTimer];
        
        _buffered = NO;
        _interrupted = YES;
        
        LoggerStream(1, @"viewWillDisappear %@", self);
    }
    else { //Preview //KxMoviePlayTypePreview
        if (_decoder) {
            
            _isStop = YES;
            
            
            [self pause];
            
            if (_moviePosition == 0 || _decoder.isEOF)
                [gHistory removeObjectForKey:_decoder.path];
            else if (!_decoder.isNetwork) {
                if(_decoder && _decoder.path )
                    [gHistory setValue:[NSNumber numberWithFloat:_moviePosition]
                                forKey:_decoder.path];
            }
            
            [_decoder closeDecode];
        }
        
        // 임시로 막음... 해결해야 될 문제...
        [self stop];
        _interrupted = NO;
        
        if (_fullscreen)
            [self fullscreenMode:NO];
        
        _buffered = NO;
        _interrupted = YES;
        
        [[UIApplication sharedApplication] setIdleTimerDisabled:_savedIdleTimer];
        
        if(delegate)
            delegate = nil;
        
        LoggerStream(1, @"viewWillDisappear %@", self);
    }
}

- (void) viewDidAppearPlay
{
    [self viewDidAppear];
}


- (void) applicationWillResignActive: (NSNotification *) notification
{
    if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
        if(self.playing) {
            isPlayingBackground = YES;
            [self pause];
        }
    }
    else { //Preview //KxMoviePlayTypePreview
        //[self pause];
    }
    LoggerStream(1, @"applicationWillResignActive");
}

- (void) applicationDidBecomeActive: (NSNotification *) notification
{
    if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
        if(isPlayingBackground) {
            isPlayingBackground = NO;
            [self play];
            
            if([delegate respondsToSelector:@selector(playerStart)]) {
                [delegate playerStart];
            }
        }
    }
    else { //Preview //KxMoviePlayTypePreview
        //[self play];
    }
    LoggerStream(1, @"applicationDidBecomeActive");
}

- (BOOL) prefersStatusBarHidden
{
    return YES;
}

- (void) clearMemory
{
    [self didReceiveMemoryWarning];
}


#pragma mark - public

- (void) play
{
    if (self.playing)
        return;
    
    if (!_decoder.validVideo &&
        !_decoder.validAudio) {
        
        return;
    }
    
    if (_interrupted)
        return;
    
    self.decoding = NO;
    self.playing = YES;
    _interrupted = NO;
    _tickCorrectionTime = 0;
    _tickCounter = 0;

    [self asyncDecodeFrames];
    
#ifdef KXVIDEO_VIEW_CUSTOM
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self tick];
    });

    if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
      if (_decoder.validAudio)
        [self enableAudio:YES];

        [self audioMute:NO];
    }
    else { //Preview //KxMoviePlayTypePreview
        if (_decoder.validAudio)
            [self enableAudio:NO];

        [self audioMute:YES];
    }

    LoggerStream(1, @"play movie");
    
   _isStop = NO;

#else //KXVIDEO_VIEW_CUSTOM
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self tick];
    });
    
    if (_decoder.validAudio)
        [self enableAudio:YES];
    
    LoggerStream(1, @"play movie");
	
#endif //KXVIDEO_VIEW_CUSTOM
}

- (void) pause
{
    if (!self.playing)
        return;
    
    self.decoding = YES;
    self.playing = NO;
    //_interrupted = YES;
    [self enableAudio:NO];
    LoggerStream(1, @"pause movie");
}

- (void) stop
{
    LoggerStream(1, @"stop movie");

    if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
        [_decoder closeFile];
        
        [self freeBufferedFrames];
        
        if (_maxBufferedDuration > 0) {
            _minBufferedDuration = _maxBufferedDuration = 0;
        }
        
        if (_dispatchQueue) {
            _dispatchQueue = NULL;
        }
        
        //    [_glView allRelease];
        _glView = nil;
        _decoder = nil;
        //    free((__bridge void *)(_glView));
        //    free((__bridge void *)(_decoder));
    }
    else { //Preview //KxMoviePlayTypePreview
        _isStop = YES;
        _interrupted = YES;
        
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        
        [self freeBufferedFrames];
        
        // 2016.09.20. 수정.
        //_interrupted = YES;
        //[_decoder closeFile];
        
        
        if (_maxBufferedDuration > 0) {
            _minBufferedDuration = _maxBufferedDuration = 0;
        }
        
        
        //    if (_dispatchQueue) {
        //        _dispatchQueue = NULL;
        //    }
        
        // 2016.09.20. 수정.
        //    _glView  = nil;
        //    _decoder = nil;
        
        
        //    id<AudioManager> audioManager = [AudioManager audioManager];
        //    [audioManager deactivateAudioSession];
        
    }
}

- (void) playEnd
{
    LoggerStream(1, @"playEnd");
    
    // 2016.09.20. 추가..
    /////////////////////
    if(_isStop ){
        [_decoder closeFile];
        _glView  = nil;
        _decoder = nil;
        
        id<KxAudioManager> audioManager = [KxAudioManager audioManager];
        [audioManager deactivateAudioSession];
    }
    ////////////////////////////
    
    
    if(delegate){
        if([delegate respondsToSelector:@selector(playerDidStop)]) {
            [delegate playerDidStop];
        }
        
    }
    
}

- (void) setMoviePosition: (CGFloat) position
{
    BOOL playMode = self.playing;

    self.playing = NO;

    [self enableAudio:NO];
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){

        [self updatePosition:position playMode:playMode];
    });
}

- (BOOL) isPlaying
{
    return self.playing;
}

- (CGFloat) duration
{
    return _decoder.duration;
}

- (CGFloat) position
{
    return _decoder.position;
}

- (CGFloat) isEOF
{
    return _decoder.isEOF;
}

// Playing 상태가 아닐때 현재 프레임을 출력함.
- (void) updateFrame
{
    if (!_buffered) {
        // [self presentFrame];
        // [self setMoviePosition:_moviePosition];
        
        CGFloat position = _moviePosition;
        position = MIN(_decoder.duration - 1, MAX(0, position));
        
        __weak KxMoviePlayerView *weakSelf = self;
        
        if(!_dispatchQueue)
            return;
        dispatch_async(_dispatchQueue, ^{
            
            if( !self.playing )
            {
                
                {
                    __strong KxMoviePlayerView *strongSelf = weakSelf;
                    if (!strongSelf) return;
                    [strongSelf setDecoderPosition: position];
                    [strongSelf decodeFrames];
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    __strong KxMoviePlayerView *strongSelf = weakSelf;
                    if (strongSelf) {
                        //[strongSelf setMoviePositionFromDecoder];
                        [strongSelf presentFrame];
                        // [strongSelf updateHUD];
                        
                        _moviePosition = position;
                    }
                });
            }
        });
        
    }
}

- (UIImage *) getCurrentImage
{
    return [_decoder getCurrentImage];
}

- (void) recordStart
{
    if ([KxManager camType] == KxMovieCamTypeLG) {
        // LGCam에서 FFmpeg를 이용해서 녹화를 시작할 경우
        // FFmpeg가 제공하는 avio_open2 이런 함수들에서 crash가 발생한다.
        NSAssert(NO, @"record failed at LGCam.");
        
        return;
    }
    
    [_decoder recordStart];
}

- (void) recordStop
{
    if ([KxManager camType] == KxMovieCamTypeLG) {
        // LGCam에서 FFmpeg를 이용해서 녹화를 시작할 경우
        // FFmpeg가 제공하는 avio_open2 이런 함수들에서 crash가 발생한다.
        NSAssert(NO, @"record failed at LGCam.");
        return;
    }
    
    [_decoder recordStop];
}

- (BOOL) isRecord
{
    return [_decoder isRecord];
}

- (CGSize) getDecoderFrameSize
{
    return CGSizeMake(_decoder.frameWidth, _decoder.frameHeight);
}

- (void) seekTime: (CGFloat) seconds
{
    [_decoder setPosition:seconds];
}

- (void) progressDidChange: (id) sender
{
    //    NSAssert(_decoder.duration != MAXFLOAT, @"bugcheck");
    UISlider *slider = sender;
    [self setMoviePosition:slider.value * _decoder.duration];
}


#pragma mark - private

- (void) setMovieDecoder: (KxMovieDecoder *) decoder
               withError: (NSError *) error
{
    LoggerStream(2, @"setMovieDecoder");
    
    if (!error && decoder) {
        
        _decoder        = decoder;
        _dispatchQueue  = dispatch_queue_create("KxMovie", DISPATCH_QUEUE_SERIAL);
        _videoFrames    = [NSMutableArray array];
        _audioFrames    = [NSMutableArray array];
        
    
        if (_decoder.isNetwork) {
            
            _minBufferedDuration = NETWORK_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = NETWORK_MAX_BUFFERED_DURATION;
            
        } else {
            
            _minBufferedDuration = LOCAL_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = LOCAL_MAX_BUFFERED_DURATION;
        }
        
        if (!_decoder.validVideo)
            _minBufferedDuration *= 10.0; // increase for audio
                
        // allow to tweak some parameters at runtime
        if (_parameters.count) {
            
            id val;
            
            val = [_parameters valueForKey: PlayerParameterMinBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _minBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: PlayerParameterMaxBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _maxBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: PlayerParameterDisableDeinterlacing];
            if ([val isKindOfClass:[NSNumber class]])
                _decoder.disableDeinterlacing = [val boolValue];
            
            if (_maxBufferedDuration < _minBufferedDuration)
                _maxBufferedDuration = _minBufferedDuration * 2;
        }
        
        LoggerStream(2, @"buffered limit: %.1f - %.1f", _minBufferedDuration, _maxBufferedDuration);
        [self setupPresentView];
        
       
         [self restorePlay];
        
    } else {
       
        if (!_interrupted)
            [self handleDecoderMovieError: error];

    }

    if ([KxManager camType] == KxMovieCamTypeLG) {  //LG캠
        [_activityIndicatorView stopAnimating];
    }
}

- (void) restorePlay
{
    NSNumber *n = [gHistory valueForKey:_decoder.path];
    if (n)
        [self updatePosition:n.floatValue playMode:YES];
    else
        [self play];
}

- (void) setupPresentView
{
#ifdef KXVIDEO_VIEW_CUSTOM
    CGRect bounds = self.bounds;
    
    _glView = [[KxMovieGLView alloc] initWithFrame:bounds decoder:_decoder];

//    [_glView setBackgroundColor:UIColorFromRGB(0xFBF7EE)];
    
    if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
        UIView *frameView = [self frameView];
        //frameView.translatesAutoresizingMaskIntoConstraints = NO;
        //frameView.contentMode = UIViewContentModeScaleToFill;
        
        if (frameView) {
            [self insertSubview:frameView atIndex:0];
            
            //[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[frameView]-0-|" options:0 metrics:nil
            //                                                                   views:NSDictionaryOfVariableBindings(frameView)]];
            //
            //[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[frameView]-0-|" options:0 metrics:nil
            //                                                                   views:NSDictionaryOfVariableBindings(frameView)]];
            
            [frameView setAutoresizesSubviews:YES];
            [frameView setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
        }
    }
    else { //Preview //KxMoviePlayTypePreview
        UIView *frameView = [self frameView];
        frameView.translatesAutoresizingMaskIntoConstraints = NO;
        frameView.contentMode = UIViewContentModeScaleToFill;
        
        if (frameView) {
            [self insertSubview:frameView atIndex:0];
            
            [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[frameView]-0-|" options:0 metrics:nil
                                                                           views:NSDictionaryOfVariableBindings(frameView)]];
            
            [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[frameView]-0-|" options:0 metrics:nil
                                                                           views:NSDictionaryOfVariableBindings(frameView)]];
        }
    }
    
#else //KXVIDEO_VIEW_CUSTOM
    CGRect bounds = self.bounds;
    
    if (_decoder.validVideo) {
        _glView = [[KxMovieGLView alloc] initWithFrame:bounds decoder:_decoder];
    }
    
    if (!_glView) {
        
        LoggerVideo(0, @"fallback to use RGB video frame and UIKit");
        [_decoder setupVideoFrameFormat:KxVideoFrameFormatRGB];
    }
    
    UIView *frameView = [self frameView];
    frameView.contentMode = UIViewContentModeScaleAspectFit;
    frameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    
    [self insertSubview:frameView atIndex:0];
    
    self.backgroundColor = [UIColor clearColor];

#endif //KXVIDEO_VIEW_CUSTOM
}

- (UIView *) frameView
{
    return _glView;
}

- (UIView *) getGlView
{
    return _glView;
}

- (void) reloadSubView
{
    [_glView reloadSubView];
}

- (void) audioMute: (BOOL) mute
{
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    if(mute){
        [audioManager pause];
        _isAudioMute = YES;

    }else{
        [audioManager play];
        _isAudioMute = NO;
    }
}

- (void) audioCallbackFillData: (float *) outData
                     numFrames: (UInt32) numFrames
                   numChannels: (UInt32) numChannels
{

    if (_buffered) {
        memset(outData, 0, numFrames * numChannels * sizeof(float));
        return;
    }

    @autoreleasepool {
        
        while (numFrames > 0) {
            
            if (!_currentAudioFrame) {
                
                @synchronized(_audioFrames) {
                    
                    NSUInteger count = _audioFrames.count;
                    
                    if (count > 0) {
                        
                        KxAudioFrame *frame = _audioFrames[0];

#ifdef DUMP_AUDIO_DATA
                        LoggerAudio(2, @"Audio frame position: %f", frame.position);
#endif
                        if (_decoder.validVideo) {
                        
                            const CGFloat delta = _moviePosition - frame.position;
                            
                            if (delta < -0.1) {
                                
                                memset(outData, 0, numFrames * numChannels * sizeof(float));
                                break; // silence and exit
                            }
                            
                            [_audioFrames removeObjectAtIndex:0];
                            
                            if (delta > 0.1 && count > 1) {
                                continue;
                            }
                            
                        } else {
                            
                            [_audioFrames removeObjectAtIndex:0];
                            _moviePosition = frame.position;
                            _bufferedDuration -= frame.duration;
                        }
                        
                        _currentAudioFramePos = 0;
                        _currentAudioFrame = frame.samples;                        
                    }
                }
            }
            
            if (_currentAudioFrame) {
                
                const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels * sizeof(float);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                
                if (bytesToCopy < bytesLeft)
                    _currentAudioFramePos += bytesToCopy;
                else
                    _currentAudioFrame = nil;                
                
            } else {
                
                memset(outData, 0, numFrames * numChannels * sizeof(float));
                //LoggerStream(1, @"silence audio");
                break;
            }
        }
    }
}

- (void) enableAudio: (BOOL) on
{
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
            
    if (on && _decoder.validAudio) {
                
        audioManager.outputBlock = ^(float *outData, UInt32 numFrames, UInt32 numChannels) {
            
            [self audioCallbackFillData: outData numFrames:numFrames numChannels:numChannels];
        };
        
        if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
            [audioManager play];
        }
        else { //Preview //KxMoviePlayTypePreview
            [audioManager play];
        }
        
        LoggerAudio(2, @"audio device smr: %d fmt: %d chn: %d",
                    (int)audioManager.samplingRate,
                    (int)audioManager.numBytesPerSample,
                    (int)audioManager.numOutputChannels);
        
    } else {
        
        [audioManager pause];
        audioManager.outputBlock = nil;
    }
}

- (BOOL) addFrames: (NSArray *)frames
{
    if (_decoder.validVideo) {
        
        @synchronized(_videoFrames) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeVideo) {
                    [_videoFrames addObject:frame];
                    _bufferedDuration += frame.duration;
                }
        }
    }
    
    if (_decoder.validAudio) {
        
        @synchronized(_audioFrames) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeAudio) {
                    [_audioFrames addObject:frame];
                    if (!_decoder.validVideo)
                        _bufferedDuration += frame.duration;
                }
        }
        
#ifdef KXVIDEO_VIEW_CUSTOM
#else //KXVIDEO_VIEW_CUSTOM
        if (!_decoder.validVideo) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeArtwork)
                    self.artworkFrame = (KxArtworkFrame *)frame;
        }
#endif //KXVIDEO_VIEW_CUSTOM
    }
    
    return self.playing && _bufferedDuration < _maxBufferedDuration;
}

- (BOOL) decodeFrames
{
    //NSAssert(dispatch_get_current_queue() == _dispatchQueue, @"bugcheck");
    
    NSArray *frames = nil;
    
    if (_decoder.validVideo ||
        _decoder.validAudio) {
        
        frames = [_decoder decodeFrames:0];
    }
    
    if (frames.count) {
        return [self addFrames: frames];
    }
    return NO;
}

- (void) asyncDecodeFrames
{
#ifdef KXVIDEO_VIEW_CUSTOM
    if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
        if (_decoder == nil)
            return;
        
        if (self.decoding)
            return;
        
        __weak KxMoviePlayerView *weakSelf = self;
        __weak KxMovieDecoder *weakDecoder = _decoder;
        
        const CGFloat duration = _decoder.isNetwork ? .0f : 0.1f;
        //    const CGFloat duration =  0.3f;
        
        self.decoding = YES;
        dispatch_async(_dispatchQueue, ^{
            
            if (weakSelf == nil || weakDecoder == nil || _dispatchQueue == nil)
                return;
            
            __strong KxMoviePlayerView *strongSelf = weakSelf;
            if (!strongSelf.playing)
                return;
            
            BOOL good = YES;
            
            while (good) {
                
                good = NO;
                
                __strong KxMovieDecoder *decoder = weakDecoder;
                
                @autoreleasepool {
                    
                    if (weakDecoder != nil && _dispatchQueue != nil) {
                        if (decoder && (decoder.validVideo || decoder.validAudio)) {
                            
                            NSArray *frames = [decoder decodeFrames:duration];
                            if (frames.count) {
                                
                                __strong KxMoviePlayerView *strongSelf = weakSelf;
                                if (strongSelf)
                                    good = [strongSelf addFrames:frames];
                            }
                        }
                    }
                }
            }
            {
                __strong KxMoviePlayerView *strongSelf = weakSelf;
                if (strongSelf) {
                    strongSelf.decoding = NO;
                }
            }
        });
    }
    else { //Preview //KxMoviePlayTypePreview
        if (_decoder == nil)
            return;
        
        if (self.decoding)
            return;
        
        if (_interrupted)
            return;
        
        __weak KxMoviePlayerView *weakSelf = self;
        __weak KxMovieDecoder *weakDecoder = _decoder;
        
        const CGFloat duration = _decoder.isNetwork ? .0f : 0.1f;
        //    const CGFloat duration =  0.3f;
        
        self.decoding = YES;
        if( _dispatchQueue == nil )
            return;
        
        
        dispatch_async(_dispatchQueue, ^{
            
            
            __strong KxMoviePlayerView *strongSelf = weakSelf;
            if (!strongSelf.playing)
                return;
            
            BOOL good = YES;
            
            while (good) {
                
                if (!strongSelf.playing)
                    return;
                
                good = NO;
                
                __strong KxMovieDecoder *decoder = weakDecoder;
                
                @autoreleasepool {
                    
                    if (_interrupted)
                        return;
                    
                    if (weakDecoder != nil && _dispatchQueue != nil) {
                        if (decoder && (decoder.validVideo || decoder.validAudio)) {
                            if (_decoder == nil || weakSelf.isStop ){
                                return;
                            }
                            if( strongSelf.isStop )
                                return;
                            
                            NSArray *frames = [decoder decodeFrames:duration];
                            if (frames && frames.count) {
                                
                                __strong KxMoviePlayerView *strongSelf = weakSelf;
                                if (strongSelf)
                                    good = [strongSelf addFrames:frames];
                                
                                frames = nil;
                                if( strongSelf.isStop ){
                                    break;
                                }
                            }else{
                                if( strongSelf.isStop ){
                                    break;
                                }
                            }
                            
                        }
                    }
                    
                }
                
                // 09.12. 수정.
                if (!strongSelf.playing){
                    if( strongSelf.isStop )
                        break;
                    return;
                }
            }
            
            {
                __strong KxMoviePlayerView *strongSelf = weakSelf;
                if (strongSelf) {
                    strongSelf.decoding = NO;
                    //if( strongSelf.isStop )
                    [strongSelf playEnd];
                }
            }
            
            
        });
    }
    
#else //KXVIDEO_VIEW_CUSTOM
    if (_decoder == nil)
        return;
    
    if (self.decoding)
        return;
    
    __weak KxMoviePlayerView *weakSelf = self;
    __weak KxMovieDecoder *weakDecoder = _decoder;
    
    const CGFloat duration = _decoder.isNetwork ? .0f : 0.1f;
    
    self.decoding = YES;
    dispatch_async(_dispatchQueue, ^{
        if (weakSelf == nil || weakDecoder == nil || _dispatchQueue == nil)
            return;
        
        {
            __strong KxMoviePlayerView *strongSelf = weakSelf;
            if (!strongSelf.playing)
                return;
        }
        
        BOOL good = YES;
        while (good) {
            
            good = NO;
            
            @autoreleasepool {
                
                __strong KxMovieDecoder *decoder = weakDecoder;
                
                if (decoder && (decoder.validVideo || decoder.validAudio)) {
                    
                    NSArray *frames = [decoder decodeFrames:duration];
                    if (frames.count) {
                        
                        __strong KxMoviePlayerView *strongSelf = weakSelf;
                        if (strongSelf)
                            good = [strongSelf addFrames:frames];
                    }
                }
            }
        
            {
                __strong KxMoviePlayerView *strongSelf = weakSelf;
                if (strongSelf) strongSelf.decoding = NO;
            }
        });
#endif //KXVIDEO_VIEW_CUSTOM
}

- (void) tick
{
    if ([KxManager playType] == KxMoviePlayTypeGallery) { //Gallery
        if (_buffered && ((_bufferedDuration > _minBufferedDuration) || _decoder.isEOF)) {
            
            _tickCorrectionTime = 0;
            _buffered = NO;
        }
        
        CGFloat interval = 0;
        if (!_buffered) {
            interval = [self presentFrame];
            //[self presentFrame];
        }
        
        if (self.playing) {
            
            const NSUInteger leftFrames =
            (_decoder.validVideo ? _videoFrames.count : 0) +
            (_decoder.validAudio ? _audioFrames.count : 0);
            
            if (0 == leftFrames) {
                
                if (_decoder.isEOF) {
                    
                    [self pause];
                    
                    return;
                }
                
                if (_minBufferedDuration > 0 && !_buffered) {
                    
                    _buffered = YES;
                    
                }
            }
            
            if (!leftFrames ||
                !(_bufferedDuration > _minBufferedDuration)) {
                
                [self asyncDecodeFrames];
            }
            
            [self updateHUD];
            
            // 2016.08.11. 수정.
            const NSTimeInterval correction = [self tickCorrection];
            const NSTimeInterval time = MAX(interval + correction, 0.01);
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC);
            //        dispatch_after(DISPATCH_TIME_NOW, dispatch_get_main_queue(), ^(void){
            //            [self tick];
            //        });
            
            dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                [self tick];
            });
            
        }
    }
    else { //Preview //KxMoviePlayTypePreview
        if( _isStop )
        {
            return;
        }
        
        if (_buffered && ((_bufferedDuration > _minBufferedDuration) || _decoder.isEOF)) {
            
            _tickCorrectionTime = 0;
            _buffered = NO;
        }
        
        CGFloat interval = 0;
        if (!_buffered) {
            interval = [self presentFrame];
            //[self presentFrame];
        }
        
        if (self.playing) {
            
            const NSUInteger leftFrames =
            (_decoder.validVideo ? _videoFrames.count : 0) +
            (_decoder.validAudio ? _audioFrames.count : 0);
            
            if (0 == leftFrames) {
                
                if (_decoder.isEOF) {
                    
                    [self pause];
                    
                    return;
                }
                
                if (_minBufferedDuration > 0 && !_buffered) {
                    
                    _buffered = YES;
                    
                }
            }
            
            if (!leftFrames ||
                !(_bufferedDuration > _minBufferedDuration)) {
                
                if( _isStop )
                    return;
                
                [self asyncDecodeFrames];
            }
            
            [self updateHUD];
            
            //        const NSTimeInterval correction = [self tickCorrection];
            //        const NSTimeInterval time = MAX(interval + correction, 0.01);
            //        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC);
            
            dispatch_after(DISPATCH_TIME_NOW, dispatch_get_main_queue(), ^(void){
                if( !_isStop )
                    [self tick];
                else{
                    //[NSThread sleepForTimeInterval:1];
                    return;
                }
            });
            
            //        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            //            [self tick];
            //        });
            
        }
    }
}

- (CGFloat) tickCorrection
{
    if (_buffered)
        return 0;
    
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (!_tickCorrectionTime) {
        
        _tickCorrectionTime = now;
        _tickCorrectionPosition = _moviePosition;
        return 0;
    }
    
    NSTimeInterval dPosition = _moviePosition - _tickCorrectionPosition;
    NSTimeInterval dTime = now - _tickCorrectionTime;
    NSTimeInterval correction = dPosition - dTime;
    
    //if ((_tickCounter % 200) == 0)
    //    LoggerStream(1, @"tick correction %.4f", correction);
    
#ifdef KXVIDEO_VIEW_CUSTOM
    if (correction > 3.f || correction < -3.f) {
#else //KXVIDEO_VIEW_CUSTOM
    if (correction > 1.f || correction < -1.f) {
#endif //KXVIDEO_VIEW_CUSTOM
        
        LoggerStream(1, @"tick correction reset %.2f", correction);
        correction = 0;
        _tickCorrectionTime = 0;
    }
    
    return correction;
}

- (CGFloat) presentFrame
{
    CGFloat interval = 0;
    
    if (_decoder.validVideo) {
        
        KxVideoFrame *frame;
        
        @synchronized(_videoFrames) {
            
            if (_videoFrames.count > 0) {
                
                frame = _videoFrames[0];
                [_videoFrames removeObjectAtIndex:0];
                _bufferedDuration -= frame.duration;
            }
        }
        
        if (frame)
            interval = [self presentVideoFrame:frame];
        
    } else if (_decoder.validAudio) {
        
        //interval = _bufferedDuration * 0.5;
        
        if (self.artworkFrame) {
            
            self.artworkFrame = nil;
        }
    }
    
    return interval;
}

-(void)networkFailCheck{
    if (self.playing) {
        networkFailCount++;
        
        NSLog(@"networkFailCount %ld",(long)networkFailCount);
        
        if(delegate && [delegate respondsToSelector:@selector(networkFailCount:tag:)]) {
            [delegate networkFailCount:networkFailCount tag:self.tag];
        }
        
        if (networkFailCount == 30) {
            if (networkTimer) {
                [networkTimer invalidate];
                networkTimer = nil;
            }
        }
        else if (networkFailCount % 5) {
            [self restorePlay];
        }
    }
}

- (CGFloat) presentVideoFrame: (KxVideoFrame *) frame
{
#ifdef KXVIDEO_VIEW_CUSTOM
    if (self.delegate && [self.delegate respondsToSelector:@selector(playerRenderWidth:height:)]) {
        [self.delegate playerRenderWidth:frame.width height:frame.height];
    }
    
    [_glView render:frame];
    
    _moviePosition = frame.position;
    
    return frame.duration;

#else //KXVIDEO_VIEW_CUSTOM
    if (_glView) {
        
        [_glView render:frame];
    }
    
    _moviePosition = frame.position;
    
    return frame.duration;
    
#endif //KXVIDEO_VIEW_CUSTOM
}

- (void) fullscreenMode: (BOOL) on
{
    _fullscreen = on;
    UIApplication *app = [UIApplication sharedApplication];
    [app setStatusBarHidden:on withAnimation:UIStatusBarAnimationNone];
    // if (!self.presentingViewController) {
    //[self.navigationController setNavigationBarHidden:on animated:YES];
    //[self.tabBarController setTabBarHidden:on animated:YES];
    // }
}

- (void) setMoviePositionFromDecoder
{
    _moviePosition = _decoder.position;
}

- (void) setDecoderPosition: (CGFloat) position
{
    _decoder.position = position;
}

- (void) updateHUD
{
    const CGFloat position = _moviePosition -_decoder.startTime;
    
    if(position < 0){
        return;
    }
    
    if(delegate){
        if(!isRealPlayStart){
            if([delegate respondsToSelector:@selector(playerDidStart)]) {
                [delegate playerDidStart];
            }
            
            if([delegate respondsToSelector:@selector(playerDidStartWithTag:)]) {
                [delegate playerDidStartWithTag:self.tag];
            }
            
            isRealPlayStart = YES;
        }
    }

}

- (void) updatePosition: (CGFloat) position
               playMode: (BOOL) playMode
{
    [self freeBufferedFrames];
    
    position = MIN(_decoder.duration - 1, MAX(0, position));
    
    __weak KxMoviePlayerView *weakSelf = self;
    
    if(!_dispatchQueue)
        return;
    dispatch_async(_dispatchQueue, ^{
        
        if (playMode) {
            
            {
                __strong KxMoviePlayerView *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                __strong KxMoviePlayerView *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf play];
                }
            });
            
        } else {
            
            {
                __strong KxMoviePlayerView *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
                [strongSelf decodeFrames];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                __strong KxMoviePlayerView *strongSelf = weakSelf;
                if (strongSelf) {
                    
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf presentFrame];
                    [strongSelf updateHUD];
                }
            });
        }
    });
}

- (void) freeBufferedFrames
{
    @synchronized(_videoFrames) {
        [_videoFrames removeAllObjects];
    }
    
    @synchronized(_audioFrames) {
        
        [_audioFrames removeAllObjects];
        _currentAudioFrame = nil;
    }
    
    _bufferedDuration = 0;
}

- (void) handleDecoderMovieError: (NSError *) error
{
#ifdef KXVIDEO_VIEW_CUSTOM
    if (self.delegate && [self.delegate respondsToSelector:@selector(decoderError:)]) {
        [self.delegate decoderError:error];
    }
    
#else //KXVIDEO_VIEW_CUSTOM
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                                        message:[error localizedDescription]
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                                              otherButtonTitles:nil];
    
    [alertView show];

#endif //KXVIDEO_VIEW_CUSTOM
}

- (BOOL) interruptDecoder
{
    //if (!_decoder)
    //    return NO;
    return _interrupted;
}

@end
