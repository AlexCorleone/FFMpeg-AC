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
        [weakSelf.playImageView setImage:resultImage];
    }];
    [self.viewModel testFF];
    
}


#pragma mark - Setter && Getter

- (UIImageView *)playImageView {
    if (!_playImageView) {
        self.playImageView = [UIImageView new];
        [_playImageView setFrame:self.view.bounds];
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
