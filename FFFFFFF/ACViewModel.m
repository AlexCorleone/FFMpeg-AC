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
}
/**  */
@property (nonatomic,strong) NSOperationQueue *imageQueue;
/** displayLink */
@property (nonatomic, strong) CADisplayLink *timer;

@end

@implementation ACViewModel

#pragma mark - LifeCycle

- (instancetype)init {
    self = [super init];
    if (self) {
        self.imageQueue = [[NSOperationQueue alloc] init];
        self.imageQueue.name = @"Alex.ImagePlayQueue";
//        self.imageQueue.maxConcurrentOperationCount = 1;
        __weak typeof(self) weakSelf = self;
        weakSelf.renderHelper = [ACRenderHelper new];
    }
    return self;
}
- (void)dealloc {
    
}

#pragma mark - Private

- (void)testFF {
    [self.imageQueue addOperationWithBlock:^{
        [self clearVideoData];
        [self initFormatContext];
        [self initVideoDecoder];
        [self initAudioDecoder];
        self.timer = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkTimerAction:)];
        [self.timer addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        [[NSRunLoop currentRunLoop] run];
    }];
}

- (void)clearVideoData {
    avformat_close_input(&formatContext);
    avcodec_close(videoCodecContext);
    avcodec_free_context(&videoCodecContext);
    av_packet_free(&videoPacket);
    av_frame_free(&pFrameYUV);
    av_frame_free(&pFrameRGBA);
    
    av_free(out_buffer);
    av_free(img_convert_ctx);
    [self.timer invalidate];
    self.timer = nil;
    frameCount = 0;
}

- (void)displayLinkTimerAction:(CADisplayLink *)timer {
    if (av_read_frame(formatContext, videoPacket) < 0) {
        //读取结束
        [self clearVideoData];
        return;
    }

    if (videoPacket->stream_index == video_stream_index) {
        result = avcodec_send_packet(videoCodecContext, videoPacket);
        if (result == 0) {
            result = avcodec_receive_frame(videoCodecContext, pFrameYUV);
            
            enum AVPixelFormat dst_pix_fmt = AV_PIX_FMT_RGBA;
            av_image_fill_arrays(pFrameRGBA->data, pFrameRGBA->linesize, out_buffer, dst_pix_fmt, videoCodecContext->width, videoCodecContext->height, 1);
            //转换图像格式
            sws_scale(img_convert_ctx, (const unsigned char* const*)pFrameYUV->data, pFrameYUV->linesize, 0, videoCodecContext->height,
                   pFrameRGBA->data, pFrameRGBA->linesize);
            
//            if (videoCodecContext->pix_fmt == AV_PIX_FMT_YUV420P) {
                [self videoImageWithFrame:pFrameRGBA];
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
    } else if (videoPacket->stream_index == audio_stream_index) {
        result = avcodec_send_packet(audioCodecContext, videoPacket);
         if (result == 0) {
             result = avcodec_receive_frame(audioCodecContext, pFrameAAC);
             [self audioDataWithFrame:pFrameAAC];
         }
    }
}

- (void)initFormatContext {
    /********** 初始化视频I/O上下文  ************/
    formatContext = avformat_alloc_context();
    /********** 指定上下文资源  ************/
    NSString *video = [[NSBundle mainBundle] pathForResource:@"video" ofType:@"mp4"];
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
    result = avformat_find_stream_info(formatContext, NULL);
    if (result < 0) {
        AC_FFmpeg_Logs("find stream info error!!!", result)
        return ;
    }
    NSLog(@"获取到 视频文件信息");
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
    if (self.frameImageBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.frameImageBlock(resultImage);

        });
    }
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
}

- (void)audioDataWithFrame:(AVFrame *)audioFrame {
    
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
