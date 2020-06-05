//
//  ViewController.m
//  FFFFFFF
//
//  Created by arges on 2019/7/24.
//  Copyright © 2019年 AlexCorleone. All rights reserved.
//

#import "ACViewController.h"
#import "ACViewModel.h"
#import "ASValueTrackingSlider.h"

@interface ACViewController ()<ACViewModelDelegate, ASValueTrackingSliderDelegate>

/**  */
@property (nonatomic,strong) ACViewModel *viewModel;
/**  */
@property (nonatomic,strong) UIImageView *playImageView;
/**  */
@property (nonatomic, strong) ASValueTrackingSlider *slider;
/**  */
@property (nonatomic, strong) UIButton *playButton;
/**  */
@property (nonatomic, strong) UILabel *timeLabel;
/**  */
@property (nonatomic, strong) UILabel *durationLabel;

@end

@implementation ACViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.viewModel = [ACViewModel new];
    self.viewModel.delegate = self;
    NSString *videoUrl = [[NSBundle mainBundle] pathForResource:@"1591344158121590" ofType:@"mp4"];//@"https://img.tukuppt.com/video_show/3670116/00/02/03/5b4f40c2b2fa3.mp4";//[[NSBundle mainBundle] pathForResource:@"videoh265" ofType:@"mp4"];@"https://img.tukuppt.com/video_show/3670116/00/02/03/5b4f40c2b2fa3.mp4";//
//    NSString *videoUrl = @"http://ok.renzuida.com/2002/YW4：完结篇.HD1280高清粤语中字版.mp4";
//    videoUrl = @"rtmp://60.31.193.11:9508/live/1000264_1_1";//@"rtmp://58.200.131.2:1935/livetv/hunantv";//@"live://60.31.193.11:9502?token=1860412462";//
//    videoUrl = @"rtmp://192.168.19.90:1935/live/46613724_00000000001311000041_0_0";
//    videoUrl = @"https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8";
//    videoUrl = @"https://www.lwavn.club/ycs-test/265test/playlist.m3u8";
    [self.view addSubview:self.playImageView];
    [self.playImageView addSubview:self.timeLabel];
    [self.playImageView addSubview:self.durationLabel];
    [self.playImageView addSubview:self.slider];
    [self.view addSubview:self.playButton];
    [self.viewModel startWithVideoUrl:videoUrl];
}

#pragma mark - Target Action

- (void)playButtonClickWithSender:(UIButton *)sender {
    if (sender.selected) {
        [self.viewModel pause];
    } else {
        [self.viewModel play];
    }
}

#pragma mark - ACViewModelDelegate

- (void)videoTimeDidChangeWithPlayTime:(NSTimeInterval)playTime duration:(NSTimeInterval)duration {
    self.timeLabel.text = [NSString stringWithFormat:@"time: %@", @(playTime).stringValue];
    self.durationLabel.text = [NSString stringWithFormat:@"duration: %@", @(duration).stringValue];
    self.slider.maximumValue = duration;
    self.slider.minimumValue = 0;
    self.slider.value = playTime;
}

- (void)videoDecompressDidEndWithImage:(UIImage *)resultImage {
    CGFloat ratio = resultImage.size.width > [UIScreen mainScreen].bounds.size.width ? [UIScreen mainScreen].bounds.size.width / resultImage.size.width : 1.0;
    self.playImageView.bounds = CGRectMake(0, 0, ratio * resultImage.size.width, ratio * resultImage.size.height);
    [self.playImageView setImage:resultImage];
    [self.slider setFrame:CGRectMake(30, CGRectGetHeight(self.playImageView.frame) -20, CGRectGetWidth(self.playImageView.frame) - 30 * 2, 20)];
}

- (void)videoStatusDidChangeWithIsPlaying:(BOOL)isPlaying {
    self.playButton.selected = isPlaying;
}

#pragma mark - ASValueTrackingSliderDelegate

- (void)sliderWillDisplayPopUpView:(ASValueTrackingSlider *)slider {
    [self.viewModel pause];
}

- (void)sliderDidHidePopUpView:(ASValueTrackingSlider *)slider {
    self.slider.value = slider.value;
    [self.viewModel seekWithTime:slider.value];
    [self.viewModel play];
}

#pragma mark - Setter && Getter

- (UIImageView *)playImageView {
    if (!_playImageView) {
        self.playImageView = [UIImageView new];
        [_playImageView setCenter:self.view.center];
        _playImageView.userInteractionEnabled = YES;
        [_playImageView setBackgroundColor:UIColor.blackColor];
    }
    return _playImageView;
}

- (UIButton *)playButton {
    if (!_playButton) {
        self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_playButton.layer setCornerRadius:20 / 2.0];
        [_playButton setTitle:@"播放" forState:UIControlStateNormal];
        [_playButton setTitle:@"暂停" forState:UIControlStateSelected];
        [_playButton setTitleColor:[UIColor purpleColor] forState:UIControlStateNormal];
        [_playButton setBackgroundColor:[UIColor lightGrayColor]];
        [_playButton addTarget:self action:@selector(playButtonClickWithSender:) forControlEvents:UIControlEventTouchUpInside];
        _playButton.frame = CGRectMake((UIScreen.mainScreen.bounds.size.width - 80) / 2.0, UIScreen.mainScreen.bounds.size.height - 70, 80, 40);
        _playButton.selected = YES;
    }
    return _playButton;
}

static CGFloat buttonWidth = 130;
- (UILabel *)timeLabel {
    if (!_timeLabel) {
        self.timeLabel = [UILabel new];
        _timeLabel.backgroundColor = [UIColor whiteColor];
        _timeLabel.textColor = [UIColor purpleColor];
        _timeLabel.font = [UIFont systemFontOfSize:13];
        _timeLabel.frame = CGRectMake(UIScreen.mainScreen.bounds.size.width - buttonWidth - 20, 20, buttonWidth, 20);
        _timeLabel.layer.cornerRadius = 20 / 2.0;
        _timeLabel.text = @"time:--";
    }
    return _timeLabel;
}

- (UILabel *)durationLabel {
    if (!_durationLabel) {
        self.durationLabel = [UILabel new];
        _durationLabel.backgroundColor = [UIColor whiteColor];
        _durationLabel.textColor = [UIColor purpleColor];
        _durationLabel.font = [UIFont systemFontOfSize:13];
        _durationLabel.frame = CGRectMake(UIScreen.mainScreen.bounds.size.width - buttonWidth - 20, 20 + 30, buttonWidth, 20);
        _durationLabel.layer.cornerRadius = 20 / 2.0;
        _durationLabel.text = @"duration:--";
    }
    return _durationLabel;
}


- (ASValueTrackingSlider *)slider {
    if (!_slider) {
        self.slider = [[ASValueTrackingSlider alloc] initWithFrame:CGRectZero];
        _slider.delegate = self;
        _slider.maximumValue = 1;
        _slider.minimumValue = 0;
        _slider.value = 0;
        _slider.popUpViewCornerRadius = 12.0;
        [_slider setMaxFractionDigitsDisplayed:0];
        _slider.popUpViewColor = [UIColor colorWithHue:0.55 saturation:0.8 brightness:0.9 alpha:0.7];
        _slider.font = [UIFont fontWithName:@"GillSans-Bold" size:22];
        _slider.textColor = [UIColor colorWithHue:0.55 saturation:1.0 brightness:0.5 alpha:1];
    }
    return _slider;
}

@end
