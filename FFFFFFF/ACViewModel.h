//
//  ACViewModel.h
//  FFFFFFF
//
//  Created by arges on 2019/7/24.
//  Copyright © 2019年 AlexCorleone. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "ACRenderHelper.h"
#import "ACOpenGLRenderView.h"

NS_ASSUME_NONNULL_BEGIN

@protocol ACViewModelDelegate <NSObject>

- (void)videoTimeDidChangeWithPlayTime:(NSTimeInterval)playTime duration:(NSTimeInterval)duration;
- (void)videoDecompressDidEndWithImage:(UIImage *)resultImage;
- (void)videoStatusDidChangeWithIsPlaying:(BOOL)isPlaying;

@end

@interface ACViewModel : NSObject

/** <#注释#> */
@property (nonatomic, strong) ACOpenGLRenderView *playerView;
/**  */
@property (nonatomic,strong) ACRenderHelper *renderHelper;
/**  */
@property (nonatomic, assign) id<ACViewModelDelegate> delegate;

- (void)startWithVideoUrl:(NSString *)videoUrl;
- (void)seekWithTime:(NSTimeInterval)time;
- (void)play;
- (void)pause;

@end

NS_ASSUME_NONNULL_END
