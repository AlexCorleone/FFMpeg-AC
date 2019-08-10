//
//  ACRenderHelper.h
//  FFFFFFF
//
//  Created by arges on 2019/8/1.
//  Copyright © 2019年 AlexCorleone. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/CAEAGLLayer.h>

NS_ASSUME_NONNULL_BEGIN


@interface ACRenderHelper : NSObject

/** <#注释#> */
@property (nonatomic, strong,  ) CAEAGLLayer *EAGLLayer;

- (void)renderBufferFrameWith:(uint32_t)bufferFrame layerFrame:(CGRect)layerFrame;

- (void)logRenderError;

@end

NS_ASSUME_NONNULL_END
