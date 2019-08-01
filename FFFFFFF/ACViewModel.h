//
//  ACViewModel.h
//  FFFFFFF
//
//  Created by arges on 2019/7/24.
//  Copyright © 2019年 AlexCorleone. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ACViewModel : NSObject

- (void)testFF;

@property (nonatomic, copy) void (^frameImageBlock)(UIImage *resultImage);

@end

NS_ASSUME_NONNULL_END
