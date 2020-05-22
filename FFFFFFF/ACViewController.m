//
//  ViewController.m
//  FFFFFFF
//
//  Created by arges on 2019/7/24.
//  Copyright © 2019年 AlexCorleone. All rights reserved.
//

#import "ACViewController.h"
#import "ACViewModel.h"

@interface ACViewController ()

/** <#注释#> */
@property (nonatomic,strong) ACViewModel *viewModel;

/** <#注释#> */
@property (nonatomic,strong) UIImageView *playImageView;

@end

@implementation ACViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.viewModel = [ACViewModel new];
    __weak typeof(self)weakSelf = self;
    [self.viewModel setFrameImageBlock:^(UIImage * _Nonnull resultImage) {
        CGFloat ratio = resultImage.size.width > [UIScreen mainScreen].bounds.size.width ? [UIScreen mainScreen].bounds.size.width / resultImage.size.width : 1.0;
        weakSelf.playImageView.bounds = CGRectMake(0, 0, ratio * resultImage.size.width, ratio * resultImage.size.height);
        [weakSelf.playImageView setImage:resultImage];
    }];
    [self.viewModel testFF];
}


#pragma mark - Setter && Getter

- (UIImageView *)playImageView {
    if (!_playImageView) {
        self.playImageView = [UIImageView new];
        [_playImageView setCenter:self.view.center];
        _playImageView.userInteractionEnabled = YES;
        [self.view addSubview:_playImageView];
        [_playImageView setBackgroundColor:UIColor.lightGrayColor];
    }
    return _playImageView;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.viewModel testFF];
}

@end
