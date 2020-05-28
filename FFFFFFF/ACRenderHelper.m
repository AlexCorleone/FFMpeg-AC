//
//  ACRenderHelper.m
//  FFFFFFF
//
//  Created by arges on 2019/8/1.
//  Copyright © 2019年 AlexCorleone. All rights reserved.
//


/*
 *Apple OpenGL ES https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/OpenGLES_ProgrammingGuide/Introduction/Introduction.html#//apple_ref/doc/uid/TP40008793
 *
 *
 *
 *
 *
 *
 *
 *
 *
 */

#import "ACRenderHelper.h"
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>

static NSString *const kRenderErrorKey = @"Alex.RenderErrorKey";

typedef NS_ENUM(NSUInteger, kRenderErrorCode) {
    kRenderErrorCodeInitEAGLContext = 1 <<0,
    kRenderErrorCodeInitLayer = 1 << 1,
    kRenderErrorCodeFramebufferStatus = 1 << 2,
};

#define kRenderErrorObject(errorCode, message) [NSError errorWithDomain:NSCocoaErrorDomain           \
                                                                   code:errorCode                     \
                                                               userInfo:@{kRenderErrorKey : message}]

static dispatch_semaphore_t renderSemaphore = nil;
void renderInitSemaphore() {
     renderSemaphore = dispatch_semaphore_create(1);
}

void renderInitLock(dispatch_semaphore_t semaphore){
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}
void renderInitunLock(dispatch_semaphore_t semaphore){
    dispatch_semaphore_signal(semaphore);
}

@interface ACRenderHelper()
{
    EAGLContext *_EAGLContext;
    GLuint _framebuffer;
    GLsizei _renderbufferWidth;
    GLsizei _renderbufferHeight;
    GLuint _colorRenderbuffer;
    GLuint _depthRenderbuffer;
    GLuint _texture;
    CAEAGLLayer *_EAGLLayer;
    NSError *_renderError;
    SEL _errorSel;
}
/** <#注释#> */
@property (nonatomic,strong) NSThread *EAGLThread;

@end

@implementation ACRenderHelper

#pragma mark - Life Cycle

+ (instancetype)alloc {
    id instance = [super alloc];
    if (instance) {
        renderInitSemaphore();
    }
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        renderInitLock(renderSemaphore);
        if (!self.EAGLThread) {
            self.EAGLThread = [[NSThread alloc] initWithTarget:self selector:@selector(EAGLThreadMethod:) object:nil];
            _EAGLThread.name = @"Alex.EAGLThread";
            [_EAGLThread start];
        }
        renderInitunLock(renderSemaphore);
        [self performSelector:@selector(initRender) onThread:self.EAGLThread withObject:nil waitUntilDone:NO];
    }
    return self;
}

#pragma mark - Public

- (void)renderBufferFrameWith:(uint32_t)bufferFrame layerFrame:(CGRect)layerFrame {
    _EAGLLayer.frame = layerFrame;
    _colorRenderbuffer = bufferFrame;
    _renderbufferWidth = layerFrame.size.width;
    _renderbufferHeight = layerFrame.size.height;
    
    //Creating Offscreen Framebuffer Objects
    //1.Create the framebuffer and bind it.
    //创建帧缓冲区，并绑定。
    //    GLuint framebuffer;
    glGenFramebuffers(1, &_framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    
    //2.Create a color renderbuffer, allocate storage for it, and attach it to the framebuffer’s color attachment point.
    //创建颜色渲染缓冲区，按照 width、 height 为其分配内存大小；并绑定到缓冲区的颜色附加点。
    //    GLsizei renderbufferWidth = 440, renderbufferHeight = 560;
    //    GLuint colorRenderbuffer;
    glGenRenderbuffers(1, &_colorRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, _renderbufferWidth, _renderbufferHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorRenderbuffer);
    
    //3.Create a depth or depth/stencil renderbuffer, allocate storage for it, and attach it to the framebuffer’s depth attachment point.
    //    GLuint depthRenderbuffer;
//    glGenRenderbuffers(1, &_depthRenderbuffer);
//    glBindRenderbuffer(GL_RENDERBUFFER, _depthRenderbuffer);
//    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, _renderbufferWidth, _renderbufferHeight);
//    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthRenderbuffer);
    
    //4.Test the framebuffer for completeness. This test only needs to be performed when the framebuffer’s configuration changes.
    //帧缓冲区配置发生变化时、帧缓冲区完整性检测
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER) ;
    if(status != GL_FRAMEBUFFER_COMPLETE) {
        NSString *errorMessage = [NSString stringWithFormat:@"failed to make complete framebuffer object %x", status];
        _renderError = kRenderErrorObject(kRenderErrorCodeFramebufferStatus, errorMessage);
        return ;
    }
    //Using Framebuffer Objects to Render to a Texture
    //1.Create the framebuffer object (using the same procedure as in Creating Offscreen Framebuffer Objects).
    
    //2.Create the destination texture, and attach it to the framebuffer’s color attachment point.
    //创建目标纹理(texture ？？？？？),并将纹理附加到帧缓冲区的颜色附加点。
    //    GLuint texture;
    glGenTextures(1, &_texture);
    glBindTexture(GL_TEXTURE_2D, _texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8,  _renderbufferWidth, _renderbufferHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _texture, 0);
    
    //Rendering to a Core Animation Layer
    
    //4.Create a color renderbuffer, allocating its storage by calling the context’s renderbufferStorage:fromDrawable: method and passing the layer object as the parameter. The width, height and pixel format are taken from the layer and used to allocate storage for the renderbuffer.
    //创建颜色渲染缓冲区，通过调用 EAGLContext 的 renderbufferStorage:fromDrawable:方法 并且传递layer<EAGLDrawable>对象 为其分配内存。layer的宽度、高度、像素格式用于创建渲染缓冲区。
    GLuint colorRenderbufferEAGL;
    glGenRenderbuffers(1, &colorRenderbufferEAGL);
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbufferEAGL);
    [_EAGLContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:_EAGLLayer];
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbufferEAGL);
    
    //5.Retrieve the height and width of the color renderbuffer.
    //从颜色渲染缓冲区取回宽度和高度
    GLint width;
    GLint height;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &width);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &height);
    
    //Clear Buffers
    //清除缓冲区 GL_DEPTH_BUFFER_BIT : 深度缓冲区 GL_COLOR_BUFFER_BIT : 颜色缓冲区
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT);
    
    
    //Discard Unneeded Renderbuffers
    //丢弃不需要的渲染缓冲区
    const GLenum discards[]  = {GL_DEPTH_ATTACHMENT};
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glDiscardFramebufferEXT(GL_FRAMEBUFFER,1, discards);
    
    
    //Present the Results to Core Animation
    //将结果呈现给核心动画
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    [_EAGLContext presentRenderbuffer:GL_RENDERBUFFER];
}

#pragma mark - Private

- (BOOL)initRender {
    _EAGLContext = [self createBestEAGLContext];
    NSLog(@"EAGLContext API : %lu  Thread: %@", (unsigned long)_EAGLContext.API, [NSThread currentThread]);
    if (!_EAGLContext) {
        _renderError = kRenderErrorObject(kRenderErrorCodeInitEAGLContext, @"EAGLContext Init Error");
        return NO;
    }
    [EAGLContext setCurrentContext: _EAGLContext];
    _EAGLLayer = [[CAEAGLLayer alloc] init];
    if (!_EAGLLayer) {
        _renderError = kRenderErrorObject(kRenderErrorCodeInitLayer, @"CAEAGLLayer Init Error");
        return NO;
    }
    NSDictionary *dict = @{kEAGLDrawablePropertyRetainedBacking : @(YES),
                           kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8
                           };
    [_EAGLLayer setDrawableProperties:dict];
    return YES;
}

- (EAGLContext*)createBestEAGLContext {
    EAGLRenderingAPI API = kEAGLRenderingAPIOpenGLES1;
OpenGLESAPICreateLabel:
    if (API == kEAGLRenderingAPIOpenGLES1) {
        API = kEAGLRenderingAPIOpenGLES3;
    } else if(API == kEAGLRenderingAPIOpenGLES3) {
        API = kEAGLRenderingAPIOpenGLES2;
    } else if(API == kEAGLRenderingAPIOpenGLES2) {
        API = kEAGLRenderingAPIOpenGLES1;
    }
    EAGLContext *context = [[EAGLContext alloc] initWithAPI:API];
    if (context == nil && API == kEAGLRenderingAPIOpenGLES1) {
        return nil;
    }
    if (context == nil) {
        goto OpenGLESAPICreateLabel;
    }
    return context;
}

#pragma mark - Render Thread

- (void)EAGLThreadMethod:(NSThread *)thread {
    [[NSRunLoop currentRunLoop] addPort:[NSPort port] forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop ] run];
}

- (void)logRenderError {
    
}

/*
 Here are the steps your app should follow to update an OpenGL ES object:
 
 1.Call glFlush on every context that may be using the object.
 2.On the context that wants to modify the object, call one or more OpenGL ES functions to change the object.
 3.Call glFlush on the context that received the state-modifying commands.
 4.On every other context, rebind the object identifier.
 */

@end
