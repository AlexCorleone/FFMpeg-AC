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
NS_ASSUME_NONNULL_BEGIN

@interface ACViewModel : NSObject

/** <#注释#> */
@property (nonatomic,strong) ACRenderHelper *renderHelper;
@property (nonatomic, copy) void (^frameImageBlock)(UIImage *resultImage);

- (void)testFF;

@end

NS_ASSUME_NONNULL_END
