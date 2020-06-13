//
//  ACOpenGLRenderView.m
//  FFFFFFF
//
//  Created by arges on 2019/8/1.
//  Copyright © 2019年 AlexCorleone. All rights reserved.
//

#import "ACOpenGLRenderView.h"
#import <QuartzCore/CAEAGLLayer.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
@interface ACOpenGLRenderView ()
{
    EAGLContext *_myContext;
    GLuint _texture;
    /** Offscreen Framebuffer */
    GLuint _framebuffer;
    GLuint _colorRenderbuffer;
    GLsizei width;
    GLsizei height;
}

@end

@implementation ACOpenGLRenderView

#pragma mark - Life Cycle

- (instancetype)init {
    self = [super init];
    if (self) {
        [self configCurrentContext];
    }
    return self;
}

+ (Class)layerClass {
    return [CAEAGLLayer class];
}

#pragma mark - Public

- (void)renderViewWith:(AVFrame *)pFrameRGBA {
    width = pFrameRGBA->width;
    height = pFrameRGBA->height;
    [self clearBuffers];
    [self createTexture];
    [self createOffScreenFrameBuffer];
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, pFrameRGBA->width, pFrameRGBA->height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pFrameRGBA->data[0]);
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self presentFinishFrame];
    });
}

#pragma mark - Private

- (void)configCurrentContext {
    if (!_myContext) {
        EAGLContext *myContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
        if (!myContext) {
            myContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
            NSLog(@"using kEAGLRenderingAPIOpenGLES2 EAGLContext");
        }
        if (!myContext) {
            myContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
            NSLog(@"using kEAGLRenderingAPIOpenGLES1 EAGLContext");
        }
        [EAGLContext setCurrentContext:myContext];
        _myContext = myContext;
        CAEAGLLayer *myEAGLLayer = (CAEAGLLayer *)self.layer;
        [_myContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:myEAGLLayer];
    }
}

- (void)createOffScreenFrameBuffer {
    if (!_myContext) {
        if (NSThread.isMainThread) {
            [self configCurrentContext];
        } else {
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self configCurrentContext];
                dispatch_semaphore_signal(semaphore);
            });
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        }
    }
    //1.Create the framebuffer and bind it.
    if (_framebuffer == 0) {
        GLuint framebuffer;
        glGenFramebuffers(1, &framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
        _framebuffer = framebuffer;
    }

    //2.Create a color renderbuffer, allocate storage for it, and attach it to the framebuffer’s color attachment point.
    if (_colorRenderbuffer == 0) {
        GLuint colorRenderbuffer;
        glGenRenderbuffers(1, &colorRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, width, height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
        _colorRenderbuffer = colorRenderbuffer;
    }

    //3.Create a depth or depth/stencil renderbuffer, allocate storage for it, and attach it to the framebuffer’s depth attachment point.
    GLuint depthRenderbuffer;
    glGenRenderbuffers(1, &depthRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, depthRenderbuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, width, height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderbuffer);
    
    //4.Test the framebuffer for completeness. This test only needs to be performed when the framebuffer’s configuration changes.
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER) ;
    if(status != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"failed to make complete framebuffer object %x", status);
    }
}

- (void)createTexture {
    // create the texture
    if (_texture == 0) {
        GLuint texture;
        glGenTextures(1, &texture);
        glBindTexture(GL_TEXTURE_2D, texture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8,  width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
        _texture = texture;
    }
}

- (void)clearBuffers {
    //Clear framebuffer attachments
    if (_framebuffer != 0) {
        glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
        glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT);
    }
}

- (void)presentFinishFrame {
    //Presenting the finished frame
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    [_myContext presentRenderbuffer:GL_RENDERBUFFER];
}

#pragma mark - Setter && Getter

@end
