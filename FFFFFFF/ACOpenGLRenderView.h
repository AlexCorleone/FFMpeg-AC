//
//  ACOpenGLRenderView.h
//  FFFFFFF
//
//  Created by arges on 2019/8/1.
//  Copyright © 2019年 AlexCorleone. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "avformat.h"

NS_ASSUME_NONNULL_BEGIN


@interface ACOpenGLRenderView : UIView

- (void)renderViewWith:(AVFrame *)pFrameRGBA;

@end

NS_ASSUME_NONNULL_END
