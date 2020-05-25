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

/** <#注释#> */
@property (nonatomic, strong) UIButton *playButton;
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
    [self.view addSubview:self.playButton];
}

#pragma mark - Target Action

- (void)playButtonClickWithSender:(UIButton *)sender {
    if (sender.selected) {
        [self.playButton setTitle:@"播放" forState:UIControlStateNormal];
        [self.viewModel pause];
    } else {
        [self.playButton setTitle:@"暂停" forState:UIControlStateNormal];
        [self.viewModel play];
    }
    sender.selected = !sender.selected;
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

- (UIButton *)playButton {
    if (!_playButton) {
        self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_playButton.layer setCornerRadius:20 / 2.0];
        [_playButton setTitle:@"播放" forState:UIControlStateNormal];
        [_playButton setTitleColor:[UIColor purpleColor] forState:UIControlStateNormal];
        [_playButton setBackgroundColor:[UIColor lightGrayColor]];
        [_playButton addTarget:self action:@selector(playButtonClickWithSender:) forControlEvents:UIControlEventTouchUpInside];
        _playButton.frame = CGRectMake((UIScreen.mainScreen.bounds.size.width - 80) / 2.0, UIScreen.mainScreen.bounds.size.height - 70, 80, 40);
    }
    return _playButton;
}


@end
