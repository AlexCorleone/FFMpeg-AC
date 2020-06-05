//
//  ACViewModel.m
//  FFFFFFF
//
//  Created by arges on 2019/7/24.
//  Copyright © 2019年 AlexCorleone. All rights reserved.
//

#import "ACViewModel.h"
#import "avformat.h"
#import "imgutils.h"
#import "swscale.h"
#import "avdevice.h"
#import "rational.h"
#import "ACRenderHelper.h"

#import <AudioToolbox/AudioToolbox.h>
#import "pixfmt.h"

#define AC_FFmpeg_Log(message) AC_FFmpeg_Logs(message, 0)
#define AC_FFmpeg_Logs(message, ffCode) NSLog(@"%s %s", message, av_err2str(ffCode));

#define AC_SEMAPHORE_LOCK(ac_semaphore) dispatch_semaphore_wait(ac_semaphore, DISPATCH_TIME_FOREVER);
#define AC_SEMAPHORE_UNLOCK(ac_semaphore) dispatch_semaphore_signal(ac_semaphore);

@interface ACViewModel()
{
    uint8_t *out_buffer;
    struct SwsContext *img_convert_ctx;
    
    AVFormatContext *formatContext;

    AVCodecContext *videoCodecContext;
    AVCodecContext *audioCodecContext;

    AVPacket *videoPacket;
    AVFrame *pFrameYUV;
    AVFrame *pFrameRGBA;
    AVFrame *pFrameAAC;
    
    AVCodecParameters *videoCodecParameters;
    AVCodec *videoCodec;
    int video_stream_index;
    
    AVCodecParameters *audioCodecParameters;
    AVCodec *audioCodec;
    int audio_stream_index;
    
    int result;
    int frameCount;
    
    NSTimeInterval _videoPlayTime;
    NSTimeInterval _audioPlayTime;
}
/** 视频资源URL */
@property (nonatomic, copy) NSString *videoUrl;
/** 解码音视频的子线程  */
@property (nonatomic,strong) NSThread *threadImageDecompr;
/**  */
@property (nonatomic, strong) dispatch_semaphore_t imageDecomprSemaphore;
/** 屏幕刷新 displayLink */
@property (nonatomic, strong) CADisplayLink *timer;

/** 视频时长 */
@property (nonatomic, assign, readonly) NSTimeInterval duration;
/** 当前播放时长 */
@property (nonatomic, assign) NSTimeInterval playTime;
/** 是否正在播放 */
@property (nonatomic, assign) BOOL isPlaying;
/** 是否是seek操作 */
@property (nonatomic, assign) BOOL isSeeking;

@end

@implementation ACViewModel

#pragma mark - LifeCycle

- (instancetype)init {
    self = [super init];
    if (self) {
//        __weak typeof(self) weakSelf = self;
//        weakSelf.renderHelper = [ACRenderHelper new];
    }
    return self;
}

- (void)dealloc {
    [self clearVideoData];
}

#pragma mark - Public

- (void)startWithVideoUrl:(NSString *)videoUrl {
    if (videoUrl && videoUrl.length != 0) {
        self.videoUrl = videoUrl;
    }
    if (!self.videoUrl || self.videoUrl.length == 0) {
        return;
    }
    [self performSelector:@selector(initVideoDecodeConfig) onThread:self.threadImageDecompr withObject:nil waitUntilDone:YES];
    [self performSelector:@selector(playOnThread) onThread:self.threadImageDecompr withObject:nil waitUntilDone:YES];
}

- (void)play {
    [self performSelector:@selector(playOnThread) onThread:self.threadImageDecompr withObject:nil waitUntilDone:YES];
}

- (void)pause {
    [self performSelector:@selector(pauseOnThread) onThread:self.threadImageDecompr withObject:nil waitUntilDone:YES];
}

- (void)seekWithTime:(NSTimeInterval)time {
    [self performSelector:@selector(seekOnThreadWithTime:) onThread:self.threadImageDecompr withObject:@(time) waitUntilDone:YES];
}

#pragma mark - Private

- (void)playOnThread {
    self.isPlaying = YES;
    self.timer = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkTimerAction:)];
    [self.timer addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(videoStatusDidChangeWithIsPlaying:)]) {
            [self.delegate videoStatusDidChangeWithIsPlaying:YES];
        }
    });
}

- (void)pauseOnThread {
    self.isPlaying = NO;
    [self.timer removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [self.timer invalidate];
    self.timer = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate && [self.delegate respondsToSelector:@selector(videoStatusDidChangeWithIsPlaying:)]) {
            [self.delegate videoStatusDidChangeWithIsPlaying:NO];
        }
    });
}

- (void)seekOnThreadWithTime:(NSNumber *)time {
    //seek时一定要设置flag = AVSEEK_FLAG_BACKWARD这样可以确保定位到附近的关键帧
    //avcodec_flush_buffers 刷新解码器
    _videoPlayTime = time.floatValue;
    _audioPlayTime = time.floatValue;
    self.isSeeking = YES;
    AVStream *videoStream = formatContext->streams[video_stream_index];
    AVStream *audioStream = formatContext->streams[audio_stream_index];
    av_seek_frame(formatContext, video_stream_index, (time.floatValue * videoStream->time_base.den / (videoStream->time_base.num)), AVSEEK_FLAG_BACKWARD);
    avcodec_flush_buffers(videoCodecContext);
    av_seek_frame(formatContext, audio_stream_index, (time.floatValue * audioStream->time_base.den / (videoStream->time_base.num)), AVSEEK_FLAG_BACKWARD);
    avcodec_flush_buffers(audioCodecContext);
//    avformat_seek_file(<#AVFormatContext *s#>, <#int stream_index#>, <#int64_t min_ts#>, <#int64_t ts#>, <#int64_t max_ts#>, <#int flags#>)
}

- (void)clearVideoData {
    [self pause];
    frameCount = 0;
    avformat_close_input(&formatContext);
    avcodec_close(videoCodecContext);
    avcodec_free_context(&videoCodecContext);
    av_packet_free(&videoPacket);
    av_frame_free(&pFrameYUV);
    av_frame_free(&pFrameRGBA);
    av_free(out_buffer);
    out_buffer = NULL;
    av_free(img_convert_ctx);
    img_convert_ctx = NULL;
}

- (void)initVideoDecodeConfig {
    avformat_network_init();
    avdevice_register_all();
    [self initFormatContext];
    [self initVideoDecoder];
    [self initAudioDecoder];
}

- (void)initFormatContext {
    /********** 初始化视频I/O上下文  ************/
    formatContext = avformat_alloc_context();
    /********** 指定上下文资源  ************/
    NSString *video = self.videoUrl;
    const char *fileUrl = [video cStringUsingEncoding:NSUTF8StringEncoding];
    AVInputFormat *inputFormat = NULL;
    AVDictionary *options = NULL;
    result = avformat_open_input(&formatContext, fileUrl, inputFormat, &options);
    if (result < 0) {
        AC_FFmpeg_Logs("file open error!!! ", result)
        return ;
    }
    NSLog(@"打开资源文件");
    /**********   ************/
    AVDictionary **infoOptions;
    infoOptions = alloca(formatContext->nb_streams * sizeof(*infoOptions));
    result = avformat_find_stream_info(formatContext, NULL);
    if (result < 0) {
        AC_FFmpeg_Logs("find stream info error!!!", result)
        return ;
    }
    NSLog(@"获取到 视频文件信息");
    av_dump_format(formatContext, 0, fileUrl, 0);
}

- (void)initVideoDecoder {
    /********** 获取视频流信息  ************/
    video_stream_index = -1;
    for (int i = 0; i < formatContext->nb_streams; i++) {
        enum AVMediaType codeType = formatContext->streams[i]->codecpar->codec_type;
        NSLog(@"code_type: %@", @(codeType));
        //流的类型 codec_type 区分是视频流、音频流或者其他附加数据
        if (formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            video_stream_index = i;
            AVStream *stream = formatContext->streams[video_stream_index];
        }
    }
    NSLog(@"video_stream_index: %d", video_stream_index);
    if (video_stream_index == -1) {
        AC_FFmpeg_Log("video stream find error")
        return;
    }
    NSLog(@"获取到 video stream");
    /********** 获取视频解码器  ************/
    videoCodecParameters = formatContext->streams[video_stream_index]->codecpar;
    videoCodec = avcodec_find_decoder(videoCodecParameters->codec_id);
    if (videoCodec == NULL) {
        AC_FFmpeg_Log("avcodec cannot find video decoder error")
        return;
    }
    NSLog(@"获取到 视频解码器");
    /********** 打开视频解码器  ************/
    videoCodecContext = avcodec_alloc_context3(videoCodec);
    avcodec_parameters_to_context(videoCodecContext, videoCodecParameters);
    result = avcodec_open2(videoCodecContext, videoCodec, NULL);
    if (result < 0) {
        AC_FFmpeg_Logs("avcodec cannot open error ", result)
        return;
    }
    NSLog(@"打开 视频解码器");
    /********** 初始化视频解码变量  ************/
    videoPacket = av_packet_alloc();
    pFrameYUV = av_frame_alloc();
    pFrameRGBA = av_frame_alloc();
    
    //需要转换的图片格式
    enum AVPixelFormat dst_pix_fmt = AV_PIX_FMT_RGBA;
    size_t bufferSize = av_image_get_buffer_size(dst_pix_fmt, videoCodecContext->width, videoCodecContext->height, 1);
    out_buffer = av_malloc(bufferSize);
    img_convert_ctx = sws_getContext(videoCodecContext->width, videoCodecContext->height, videoCodecContext->pix_fmt, videoCodecContext->width, videoCodecContext->height, dst_pix_fmt, SWS_BICUBIC, NULL, NULL, NULL);
    pFrameRGBA->width = videoCodecContext->width;
    pFrameRGBA->height = videoCodecContext->height;
}

- (void)initAudioDecoder {
    /********** 获取  ************/
    audio_stream_index = -1;
    for (int i = 0; i < formatContext->nb_streams; i++) {
        enum AVMediaType codeType = formatContext->streams[i]->codecpar->codec_type;
        NSLog(@"code_type: %@", @(codeType));
        //流的类型 codec_type 区分是视频流、音频流或者其他附加数据
        if (formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            audio_stream_index = i;
            AVStream *stream = formatContext->streams[audio_stream_index];
        }
    }
    NSLog(@"audio_stream_index: %d", audio_stream_index);
    if (audio_stream_index == -1) {
        AC_FFmpeg_Log("audio stream find error")
        return;
    }
    NSLog(@"获取到 audio stream");
    /**********   ************/
    audioCodecParameters = formatContext->streams[audio_stream_index]->codecpar;
    audioCodec = avcodec_find_decoder(audioCodecParameters->codec_id);
    if (audioCodec == NULL) {
      AC_FFmpeg_Log("avcodec cannot find video decoder error")
      return;
    }
    NSLog(@"获取到 音频解码器");
    /**********   ************/
    audioCodecContext = avcodec_alloc_context3(audioCodec);
    avcodec_parameters_to_context(audioCodecContext, audioCodecParameters);
    result = avcodec_open2(audioCodecContext, audioCodec, NULL);
    if (result < 0) {
      AC_FFmpeg_Logs("avcodec cannot open error ", result)
      return;
    }
    NSLog(@"打开 音频解码器");
    pFrameAAC = av_frame_alloc();
}

- (void)videoImageWithFrame:(AVFrame *)pFrameRGBA {
    size_t bitsPerComponent = 8;//颜色分量字节大小
    size_t bitsPerPixel = 32; //一个RGBA颜色值存储的字节大小
    size_t bytesPerRow = (4 * pFrameRGBA->width);
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast;
    CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pFrameRGBA->data[0], bytesPerRow * pFrameRGBA->height, NULL);
    CGImageRef imageRef = CGImageCreate(pFrameRGBA->width, pFrameRGBA->height,
                                        bitsPerComponent, bitsPerPixel, bytesPerRow,
                                        colorSpaceRef, bitmapInfo, provider,
                                        NULL, NO, renderingIntent);
    
    UIImage *resultImage = [UIImage imageWithCGImage:imageRef];
    if (self.delegate && [self.delegate respondsToSelector:@selector(videoDecompressDidEndWithImage:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate videoDecompressDidEndWithImage:resultImage];
        });
    }
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
}

//http://ffmpeg.org/doxygen/trunk/transcode_aac_8c-example.html
- (void)audioDataWithFrame:(AVFrame *)audioFrame {

}

#pragma mark - Timer Action

- (void)displayLinkTimerAction:(CADisplayLink *)timer {
//    AC_SEMAPHORE_LOCK(self.imageDecomprSemaphore);
    if (av_read_frame(formatContext, videoPacket) < 0) {
        //读取结束
        [self pause];
        return;
    }
    NSTimeInterval oldPlayTime = self.playTime;
    [self resetPlayTimeWithStreamIndex:videoPacket->stream_index];
    if (videoPacket->stream_index == video_stream_index) {
        result = avcodec_send_packet(videoCodecContext, videoPacket);
        if (result == 0) {
            result = avcodec_receive_frame(videoCodecContext, pFrameYUV);
            enum AVPixelFormat dst_pix_fmt = AV_PIX_FMT_RGBA;
            av_image_fill_arrays(pFrameRGBA->data, pFrameRGBA->linesize, out_buffer, dst_pix_fmt, videoCodecContext->width, videoCodecContext->height, 1);
            //转换图像格式
            sws_scale(img_convert_ctx, (const unsigned char* const*)pFrameYUV->data, pFrameYUV->linesize, 0, videoCodecContext->height,
                   pFrameRGBA->data, pFrameRGBA->linesize);
            if (self.isSeeking) {
                if (pFrameYUV->pict_type == AV_PICTURE_TYPE_I) {
                    self.isSeeking = NO;
                } else {
                    //处理seek时\seek的不是关键帧
                    if (self.playTime >= oldPlayTime) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (self.delegate && [self.delegate respondsToSelector:@selector(videoTimeDidChangeWithPlayTime:duration:)]) {
                                [self.delegate videoTimeDidChangeWithPlayTime:self.playTime duration:self.duration];
                            }
                        });
                    }
                    return;
                }
            }
            [self videoImageWithFrame:pFrameRGBA];
            {
                //            if (videoCodecContext->pix_fmt == AV_PIX_FMT_YUV420P) {
                //            }
                //            if (pFrameYUV->pict_type == AV_PICTURE_TYPE_I) {
                //                AC_FFmpeg_Log("IIIIIIIIIIIIII帧")
                //            } else if (pFrameYUV->pict_type == AV_PICTURE_TYPE_P) {
                //                AC_FFmpeg_Log("PPPPPPPPPPPPPP帧")
                //            } else if (pFrameYUV->pict_type == AV_PICTURE_TYPE_B) {
                //                AC_FFmpeg_Log("BBBBBBBBBBBBBB帧")
                //            }
                //            frameCount++;
                //            NSLog(@"解码绘制第 %d帧s数据", frameCount);
            }
        }
    } else if (videoPacket->stream_index == audio_stream_index) {
        result = avcodec_send_packet(audioCodecContext, videoPacket);
         if (result == 0) {
             result = avcodec_receive_frame(audioCodecContext, pFrameAAC);
             [self audioDataWithFrame:pFrameAAC];
         }
    }

    if (self.playTime > oldPlayTime) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.delegate && [self.delegate respondsToSelector:@selector(videoTimeDidChangeWithPlayTime:duration:)]) {
                [self.delegate videoTimeDidChangeWithPlayTime:self.playTime duration:self.duration];
            }
        });
    }
//    AC_SEMAPHORE_UNLOCK(self.imageDecomprSemaphore);
}

- (void)resetPlayTimeWithStreamIndex:(int)streamIndex {
    AVStream *stream = formatContext->streams[streamIndex];
    if (video_stream_index == streamIndex) {
        _videoPlayTime = (NSTimeInterval)(videoPacket->pts * stream->time_base.num / (stream->time_base.den));
        NSLog(@"-------------------------video frame time: %lf pts: %lld duration: %lld", _videoPlayTime, videoPacket->pts, videoPacket->duration);
    } else if(audio_stream_index == streamIndex) {
        _audioPlayTime = (NSTimeInterval)(videoPacket->pts * stream->time_base.num / (stream->time_base.den));
        NSLog(@"-------------------------audio frame time: %lf pts: %lld duration: %lld", _videoPlayTime, videoPacket->pts, videoPacket->duration);
    }

}

- (void)avframeToRGBFrameWithFrame:(AVFrame *)frame stream_index:(unsigned int)stream_index {
    int result;
    AVFrame *yuvFrame = frame;
    AVOutputFormat *outputFormat = NULL;
    AVFormatContext *formatContext = NULL;
    AVCodec *encodec = NULL;
    AVStream *videoStream = NULL;
    AVCodecContext *codecContext = NULL;
    AVPacket *packet = NULL;
    
    avformat_network_init();
    avdevice_register_all();
    /********** AVOutputFormat * ************/
    void *opaque = NULL;
    enum AVCodecID videoCodeId = AV_CODEC_ID_MPEG4;
    enum AVCodecID audioCodeId = AV_CODEC_ID_AC3;
    char *outputName = "avi";
outputCondationLabel:
    NSLog(@"\n\n  AVOutputFormat->video_codec == (AV_CODEC_ID_MPEG4 || AV_CODEC_ID_H264)\n");
    for (int i = 0; ; i++) {
      const AVOutputFormat * output = av_muxer_iterate(&opaque);
        if (output == NULL) {
            break;
        }
        if (output->video_codec == videoCodeId
            && output->audio_codec == audioCodeId) {
            printf("OutputFormat -> name:%s,     longName:%s,      mimeType:%s     audioCode: %u,    videoCode: %u\n", output->name, output->long_name, output->mime_type, output->audio_codec, output->video_codec);
            if (/*strcmp("f4v", output->name) == 0*//*h264*/
                strcmp(outputName, output->name) == 0) {
                outputFormat = (AVOutputFormat *)output;
            }
        }
    }
    NSLog(@"\n\n");
    if (outputFormat == NULL) {
        if (videoCodeId == AV_CODEC_ID_MPEG4 && audioCodeId == AV_CODEC_ID_AC3) {
            videoCodeId = AV_CODEC_ID_H264;
            audioCodeId = AV_CODEC_ID_AAC;
            goto outputCondationLabel;
        }
        AC_FFmpeg_Log("outputFormat Error !!!!");
        return;
    }
    /********** AVFormatContext * ************/
    formatContext = avformat_alloc_context();
    formatContext->oformat = outputFormat;
    /**********  AVIOContext * ************/
    NSString *encoderFilePath = [self outputFormatFilePath];
    result = avio_open(&formatContext->pb, [NSString stringWithFormat:@"%@/codecVideo.avi", encoderFilePath].UTF8String, AVIO_FLAG_READ_WRITE);
    if (result < 0 ) {
        AC_FFmpeg_Logs("编码视频输出文件打开失败！！！！", result);
        return;
    }
    /********** AVCodec *  ************/
    encodec = avcodec_find_encoder(outputFormat->video_codec);
    if (encodec == NULL) {
        AC_FFmpeg_Log("encoder init error!!!");
        return;
    }
    /**********  AVCodecContext * ************/
    codecContext = avcodec_alloc_context3(encodec);
    if (codecContext == NULL) {
        AC_FFmpeg_Log("codecContext init error!!!");
        return;
    }
    result = avcodec_is_open(codecContext);
    if (result != 0) {
       result = avcodec_open2(codecContext, encodec, NULL);
        if (result != 0) {
            AC_FFmpeg_Logs("error Codec Can not open", result);
            return;
        }
    }
    /********** AVStream *  ************/
    videoStream = avformat_new_stream(formatContext, encodec);
    videoStream->time_base.num = 1;
    videoStream->time_base.den = 25;
    if (videoStream == NULL) {
        AC_FFmpeg_Log("video Stream Error !!!!");
        return ;
    }
    avcodec_parameters_to_context(codecContext, videoStream->codecpar);
    codecContext->codec_id = outputFormat->video_codec;
    codecContext->codec_type = AVMEDIA_TYPE_VIDEO;
    codecContext->pix_fmt = AV_PIX_FMT_YUV420P;
    codecContext->width = yuvFrame->width;
    codecContext->height = yuvFrame->height;
    codecContext->bit_rate = 400000;
    codecContext->gop_size = 15;
    //最大B帧数
    codecContext->max_b_frames = 3;
    
    //编码帧率，每秒多少帧。下面表示1秒25帧
    codecContext->time_base.num = 1;
    codecContext->time_base.den = 25;
    
    
//    result = avformat_write_header(formatContext, NULL);
//    if (result != AVSTREAM_INIT_IN_WRITE_HEADER) {
//        AC_FFmpeg_Logs("format header write error", result);
//        return;
//    }
    /**********  AVPacket * ************/
    packet = av_packet_alloc();
    int pictureSize = av_image_get_buffer_size(codecContext->pix_fmt, codecContext->width, codecContext->height, 1);
    result = av_new_packet(packet, pictureSize);
    if (result != 0) {
        AC_FFmpeg_Logs("packet init Error !!!" , result)
        return;
    }
    
    while (1) {
        result = avcodec_send_frame(codecContext, yuvFrame);
        if (result != 0) {
            AC_FFmpeg_Logs("codec send Error !!!" , result)
            goto codecSendError;
        }
        avcodec_receive_packet(codecContext, packet);
        packet->stream_index =  stream_index * (videoStream->time_base.den) / ((videoStream->time_base.num) * 25);
        packet->stream_index = videoStream->index;
        result = av_write_frame(formatContext, packet);
        if (result < 0) {
            AC_FFmpeg_Logs("frame Write Error !!!" , result)
            continue;
        }
    }
codecSendError:
    av_packet_unref(packet);

    
    
    //    result = avformat_find_stream_info(formatContext, NULL);
    //    if (result < 0) {
    //        NSLog(@"find stream info error!!!%s", av_err2str(result));
    //        return ;
    //    }
    //    NSLog(@"获取到 视频文件信息");
    //    const AVCodec * codec = NULL;
    //    opaque = NULL;
    //    NSLog(@"\n\n  AVCodec->type == ()\n");
    //    while (1) {
    //        const AVCodec * codecItem = av_codec_iterate(&opaque);
    //        if (codecItem == NULL) {
    //            break;
    //        } else {
    //            printf("Codec -> name:%s,     longName:%s,      type:%d       codeId: %u\n", codecItem->name, codecItem->long_name, codecItem->type,  codecItem->id);
    //        }
    //
    //    }
    //    NSLog(@"\n\n");
}

- (NSString *)filePath {
    NSString *outputPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *outputFile = [outputPath stringByAppendingString:@"/result.yuv"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:outputFile]) {
        NSError *fileError = nil;
        [[NSFileManager defaultManager] removeItemAtPath:outputFile error:&fileError];
        if (fileError) {
            NSLog(@"输出文件删除失败");
            return nil;
        }
    }
    [ACViewModel AC_createFileWithName:@"result.MP4" path:outputPath content:[NSData data]];
    return outputPath;
}

- (NSString *)outputFormatFilePath {
    NSString *outputPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *outputFile = [outputPath stringByAppendingString:@"/codecVideo.avi"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:outputFile]) {
        NSError *fileError = nil;
        [[NSFileManager defaultManager] removeItemAtPath:outputFile error:&fileError];
        if (fileError) {
            NSLog(@"输出文件删除失败");
            return nil;
        }
    }
    [ACViewModel AC_createFileWithName:@"codecVideo.avi" path:outputPath content:[NSData data]];
    return outputPath;
}

+ (NSString *)AC_createFileWithName:(NSString *)fileName path:(NSString *)filePath content:(NSData *)content {
    NSString *fileUrl = [NSString stringWithFormat:@"%@/%@", filePath, fileName];
    NSFileManager *fileManager = [[NSFileManager alloc]init];
    BOOL result = [fileManager createFileAtPath:fileUrl contents:content attributes:nil];
    if (result) {
        return fileUrl;
    }
    return nil;
}

- (void)threadInitAction:(NSObject *)object {
    [[NSRunLoop currentRunLoop] addPort:[NSPort port] forMode:NSRunLoopCommonModes];
    [[NSRunLoop currentRunLoop] run];
}

#pragma mark - Setter && Getter

- (NSThread *)threadImageDecompr {
    if (!_threadImageDecompr) {
        self.threadImageDecompr = [[NSThread alloc] initWithTarget:self selector:@selector(threadInitAction:) object:nil];
        _threadImageDecompr.name = @"Alex.DecompressImageThread";
        [_threadImageDecompr start];
    }
    return _threadImageDecompr;
}

- (dispatch_semaphore_t)imageDecomprSemaphore {
    if (!_imageDecomprSemaphore) {
        self.imageDecomprSemaphore = dispatch_semaphore_create(1);
    }
    return _imageDecomprSemaphore;
}

- (NSTimeInterval)duration {
    
    return (int)formatContext->duration / AV_TIME_BASE;
}

- (NSTimeInterval)playTime {
    return (int)(_videoPlayTime > _audioPlayTime ? _videoPlayTime : _audioPlayTime);
}

@end


//unsigned long data0_len = strlen((const char *)data0);
//unsigned long data1_len = strlen((const char *)data1);
//unsigned long data2_len = strlen((const char *)data2);
//unsigned long unit = sizeof(data0[0]);
//uint8_t *src = malloc(sizeof(uint8_t) * (data0_len + data1_len + data2_len));
//int data0_count = (int)(data0_len / unit);
//int data1_count = (int)(data1_len / unit);
//int data2_count = (int)(data1_len / unit);
//
//int i = 0;
//uint8_t dst;
//while (i < data0_count) {
//    src[i] = data0[i];
//    i++;
//}
//i = 0;
//while (i < data1_count) {
//    src[i + data0_len] = data1[i];
//    i++;
//}
//i = 0;
//while (i < data2_count) {
//    src[i + data0_len + data1_len] = data2[i];
//    i++;
//    }


//                    fwrite(pFrameYUV->data[0], 1, frame_size, fp_yuv);    //Y
//                    fwrite(pFrameYUV->data[1], 1, frame_size / 4, fp_yuv);  //U
//                    fwrite(pFrameYUV->data[2], 1, frame_size / 4, fp_yuv);  //V




