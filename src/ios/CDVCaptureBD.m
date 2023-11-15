/*
 Copyright (c) 2023 BlackBerry Limited. All Rights Reserved.
 Some modifications to the original Cordova Media Capture plugin
 from https://github.com/apache/cordova-plugin-media-capture/

 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */


#import <BlackBerryDynamics/GD/GDFileManager.h>

#ifdef BBD_CAPACITOR
#import "BbdStoragePathHelper.h"
#else
#import <BbdBasePlugin/BbdStoragePathHelper.h>
#endif

#import "CDVCaptureBD.h"

#import "CDVFileBD.h"
#import "CDVLocalFilesystemBD.h"

#import <Cordova/CDVAvailability.h>

#define kW3CMediaFormatHeight @"height"
#define kW3CMediaFormatWidth @"width"
#define kW3CMediaFormatCodecs @"codecs"
#define kW3CMediaFormatBitrate @"bitrate"
#define kW3CMediaFormatDuration @"duration"
#define kW3CMediaModeType @"type"


#pragma mark - MediaStorageHelper

@interface MediaStorageHelper: NSObject

+ (NSString *)audioPath:(NSString *)path;
+ (NSString *)imagePath:(NSString *)path;
+ (NSString *)videoPath:(NSString *)path;
+ (void)copyItemAtPath:(NSString *)path toSecurePath:(NSString *)securePath;

@end

@implementation MediaStorageHelper

+ (NSString *)path:(NSString *)path for:(NSString *)dir
{
    return [NSString stringWithFormat:@"%@/%@", [BbdStoragePathHelper fullPathWithAppkineticsPath:dir], path];
}

+ (NSString *)imagePath:(NSString *)path
{
    return [MediaStorageHelper path:path for:@"media/images"];
}

+ (NSString *)videoPath:(NSString *)path
{
    return [MediaStorageHelper path:path for:@"media/video"];
}

+ (NSString *)audioPath:(NSString *)path
{
    return [MediaStorageHelper path:path for:@"media/audio"];
}

+ (void)copyItemAtPath:(NSString *)path toSecurePath:(NSString *)securePath
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
    {
        @throw([NSException exceptionWithName:NSGenericException reason:@"File not exist in FS" userInfo:nil]);
    }

    NSData* data = [NSData dataWithContentsOfFile:path];

    if (![[GDFileManager defaultManager] createFileAtPath:securePath contents:data attributes:nil])
    {
        @throw([NSException exceptionWithName:NSGenericException reason:@"Can`t create file in secure storage!" userInfo:nil]);
    }
}

@end

@implementation NSBundle (PluginExtensions)

+ (NSBundle*) pluginBundle:(CDVPlugin*)plugin {
    NSBundle* bundle = [NSBundle bundleWithPath: [[NSBundle mainBundle] pathForResource:NSStringFromClass([plugin class]) ofType: @"bundle"]];
    return bundle;
}
@end

#define PluginLocalizedString(plugin, key, comment) [[NSBundle pluginBundle:(plugin)] localizedStringForKey:(key) value:nil table:nil]

@implementation CDVImagePickerBD

@synthesize quality;
@synthesize callbackId;
@synthesize mimeType;

- (uint64_t)accessibilityTraits
{
    NSString* systemVersion = [[UIDevice currentDevice] systemVersion];

    if (([systemVersion compare:@"4.0" options:NSNumericSearch] != NSOrderedAscending)) { // this means system version is not less than 4.0
        return UIAccessibilityTraitStartsMediaSession;
    }

    return UIAccessibilityTraitNone;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIViewController*)childViewControllerForStatusBarHidden {
    return nil;
}

- (void)viewWillAppear:(BOOL)animated {
    SEL sel = NSSelectorFromString(@"setNeedsStatusBarAppearanceUpdate");
    if ([self respondsToSelector:sel]) {
        [self performSelector:sel withObject:nil afterDelay:0];
    }

    [super viewWillAppear:animated];
}

@end

#pragma mark - CDVCaptureBD

@implementation CDVCaptureBD
@synthesize inUse;

- (void)pluginInitialize
{
    self.inUse = NO;
}

- (void)captureAudio:(CDVInvokedUrlCommand*)command
{
    NSString* callbackId = command.callbackId;
    NSDictionary* options = [command argumentAtIndex:0];

    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }

    NSNumber* duration = [options objectForKey:@"duration"];
    // the default value of duration is 0 so use nil (no duration) if default value
    if (duration) {
        duration = [duration doubleValue] == 0 ? nil : duration;
    }
    CDVPluginResult* result = nil;

    if (NSClassFromString(@"AVAudioRecorder") == nil) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:CAPTURE_NOT_SUPPORTED];
    } else if (self.inUse == YES) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:CAPTURE_APPLICATION_BUSY];
    } else {
        // all the work occurs here
        CDVAudioRecorderViewControllerBD* audioViewController = [[CDVAudioRecorderViewControllerBD alloc] initWithCommand:self duration:duration callbackId:callbackId];

        // Now create a nav controller and display the view...
        CDVAudioNavigationControllerBD* navController = [[CDVAudioNavigationControllerBD alloc] initWithRootViewController:audioViewController];

        self.inUse = YES;

        [self.viewController presentViewController:navController animated:YES completion:nil];
    }

    if (result) {
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }
}

- (void)captureImage:(CDVInvokedUrlCommand*)command
{
    NSString* callbackId = command.callbackId;
    NSDictionary* options = [command argumentAtIndex:0];

    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }

    // options could contain limit and mode neither of which are supported at this time
    // taking more than one picture (limit) is only supported if provide own controls via cameraOverlayView property
    // can support mode in OS

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        NSLog(@"Capture.imageCapture: camera not available.");
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:CAPTURE_NOT_SUPPORTED];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    } else {
        if (pickerController == nil) {
            pickerController = [[CDVImagePickerBD alloc] init];
        }

        [self showAlertIfAccessProhibited];
        pickerController.delegate = self;
        pickerController.sourceType = UIImagePickerControllerSourceTypeCamera;
        pickerController.allowsEditing = NO;
        if ([pickerController respondsToSelector:@selector(mediaTypes)]) {
            // iOS 3.0
            pickerController.mediaTypes = [NSArray arrayWithObjects:(NSString*)kUTTypeImage, nil];
        }

        /*if ([pickerController respondsToSelector:@selector(cameraCaptureMode)]){
            // iOS 4.0
            pickerController.cameraCaptureMode = UIImagePickerControllerCameraCaptureModePhoto;
            pickerController.cameraDevice = UIImagePickerControllerCameraDeviceRear;
            pickerController.cameraFlashMode = UIImagePickerControllerCameraFlashModeAuto;
        }*/
        // CDVImagePickerBD specific property
        pickerController.callbackId = callbackId;
        pickerController.modalPresentationStyle = UIModalPresentationCurrentContext;
        [self.viewController presentViewController:pickerController animated:YES completion:nil];
    }
}

/* Process a still image from the camera.
 * IN:
 *  UIImage* image - the UIImage data returned from the camera
 *  NSString* callbackId
 */
- (CDVPluginResult*)processImage:(UIImage*)image type:(NSString*)mimeType forCallbackId:(NSString*)callbackId
{
    CDVPluginResult* result = nil;

    @try {
        double imageQuality = 0.5;
        NSData* data = nil;

        if (mimeType && [mimeType isEqualToString:@"image/png"]) {
            data = UIImagePNGRepresentation(image);
        } else {
            data = UIImageJPEGRepresentation(image, imageQuality);
        }

        GDFileManager* fm = [GDFileManager defaultManager];

        NSString* path;
        int i = 1;
        do {
            path = [MediaStorageHelper imagePath:[NSString stringWithFormat:@"photo_%03d.jpg", i++]];
        } while ([fm fileExistsAtPath:path]);

        if (![fm createFileAtPath:path contents:data attributes:nil])
        {
            @throw([NSException exceptionWithName:NSGenericException reason:@"Can`t create file in secure storage!" userInfo:nil]);
        }

        NSArray* fileArray = [NSArray arrayWithObject:[self getMediaDictionaryFromPath:path ofType:mimeType]];

        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:fileArray];
    }
    @catch (NSException* exeption) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageToErrorObject:CAPTURE_INTERNAL_ERR];
    }

    return result;
}

- (void)captureVideo:(CDVInvokedUrlCommand*)command
{
    NSString* callbackId = command.callbackId;
    NSDictionary* options = [command argumentAtIndex:0];

    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }

    // options could contain limit, duration and mode
    // taking more than one video (limit) is only supported if provide own controls via cameraOverlayView property
    NSNumber* duration = [options objectForKey:@"duration"];
    NSString* mediaType = nil;

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        // there is a camera, it is available, make sure it can do movies
        pickerController = [[CDVImagePickerBD alloc] init];

        NSArray* types = nil;
        if ([UIImagePickerController respondsToSelector:@selector(availableMediaTypesForSourceType:)]) {
            types = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
            // NSLog(@"MediaTypes: %@", [types description]);

            if ([types containsObject:(NSString*)kUTTypeMovie]) {
                mediaType = (NSString*)kUTTypeMovie;
            } else if ([types containsObject:(NSString*)kUTTypeVideo]) {
                mediaType = (NSString*)kUTTypeVideo;
            }
        }
    }
    if (!mediaType) {
        // don't have video camera return error
        NSLog(@"Capture.captureVideo: video mode not available.");
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:CAPTURE_NOT_SUPPORTED];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        pickerController = nil;
    } else {
        [self showAlertIfAccessProhibited];

        pickerController.delegate = self;
        pickerController.sourceType = UIImagePickerControllerSourceTypeCamera;
        pickerController.allowsEditing = NO;
        // iOS 3.0
        pickerController.mediaTypes = [NSArray arrayWithObjects:mediaType, nil];

        if ([mediaType isEqualToString:(NSString*)kUTTypeMovie]){
            if (duration) {
                pickerController.videoMaximumDuration = [duration doubleValue];
            }
            //NSLog(@"pickerController.videoMaximumDuration = %f", pickerController.videoMaximumDuration);
        }

        // iOS 4.0
        if ([pickerController respondsToSelector:@selector(cameraCaptureMode)]) {
            pickerController.cameraCaptureMode = UIImagePickerControllerCameraCaptureModeVideo;
            // pickerController.videoQuality = UIImagePickerControllerQualityTypeHigh;
            // pickerController.cameraDevice = UIImagePickerControllerCameraDeviceRear;
            // pickerController.cameraFlashMode = UIImagePickerControllerCameraFlashModeAuto;
        }
        // CDVImagePickerBD specific property
        pickerController.callbackId = callbackId;
        pickerController.modalPresentationStyle = UIModalPresentationCurrentContext;
        [self.viewController presentViewController:pickerController animated:YES completion:nil];
    }
}

- (CDVPluginResult*)processVideo:(NSString*)moviePath forCallbackId:(NSString*)callbackId
{

    CDVPluginResult* result;
    NSError* error;

    @try {
        NSString* movieName = [moviePath lastPathComponent];
        NSString* securePath = [MediaStorageHelper videoPath:movieName];

        [MediaStorageHelper copyItemAtPath:moviePath toSecurePath:securePath];

        [[NSFileManager defaultManager] removeItemAtPath:moviePath error:&error];

        // create MediaFile object
        NSDictionary* fileDict = [self getMediaDictionaryFromPath:moviePath ofType:nil];
        NSArray* fileArray = [NSArray arrayWithObject:fileDict];

        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:fileArray];
    }
    @catch (NSException* exception) {
        NSLog( @"### Caught Exception Name: %@", exception.name);
        NSLog( @"### Caught Exception Reason: %@", exception.reason);
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
    }

    return result;
}

- (void)showAlertIfAccessProhibited
{
    if (![self hasCameraAccess]) {
        [self showPermissionsAlert];
    }
}

- (BOOL)hasCameraAccess
{
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];

    return status != AVAuthorizationStatusDenied && status != AVAuthorizationStatusRestricted;
}

- (void)showPermissionsAlert
{
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"]
        message:NSLocalizedString(@"Access to the camera has been prohibited; please enable it in the Settings app to continue.", nil)
        preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
    style:UIAlertActionStyleDefault
    handler:^(UIAlertAction * action)
    {
        [self returnNoPermissionError];
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", nil)
    style:UIAlertActionStyleDefault
    handler:^(UIAlertAction * action)
    {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]options:@{} completionHandler:nil];
        [self returnNoPermissionError];
    }]];
    [self.viewController presentViewController:alertController animated:YES completion:^{}];
}

- (void)returnNoPermissionError
{
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:CAPTURE_PERMISSION_DENIED];

    [[pickerController presentingViewController] dismissViewControllerAnimated:YES completion:nil];
    [self.commandDelegate sendPluginResult:result callbackId:pickerController.callbackId];
    pickerController = nil;
    self.inUse = NO;
}

- (void)getMediaModes:(CDVInvokedUrlCommand*)command
{
    // NSString* callbackId = [command argumentAtIndex:0];
    // NSMutableDictionary* imageModes = nil;
    NSArray* imageArray = nil;
    NSArray* movieArray = nil;
    NSArray* audioArray = nil;

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        // there is a camera, find the modes
        // can get image/jpeg or image/png from camera

        /* can't find a way to get the default height and width and other info
         * for images/movies taken with UIImagePickerController
         */
        NSDictionary* jpg = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:0], kW3CMediaFormatHeight,
            [NSNumber numberWithInt:0], kW3CMediaFormatWidth,
            @"image/jpeg", kW3CMediaModeType,
            nil];
        NSDictionary* png = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:0], kW3CMediaFormatHeight,
            [NSNumber numberWithInt:0], kW3CMediaFormatWidth,
            @"image/png", kW3CMediaModeType,
            nil];
        imageArray = [NSArray arrayWithObjects:jpg, png, nil];

        if ([UIImagePickerController respondsToSelector:@selector(availableMediaTypesForSourceType:)]) {
            NSArray* types = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];

            if ([types containsObject:(NSString*)kUTTypeMovie]) {
                NSDictionary* mov = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithInt:0], kW3CMediaFormatHeight,
                    [NSNumber numberWithInt:0], kW3CMediaFormatWidth,
                    @"video/quicktime", kW3CMediaModeType,
                    nil];
                movieArray = [NSArray arrayWithObject:mov];
            }
        }
    }
    NSDictionary* modes = [NSDictionary dictionaryWithObjectsAndKeys:
        imageArray ? (NSObject*)                          imageArray:[NSNull null], @"image",
        movieArray ? (NSObject*)                          movieArray:[NSNull null], @"video",
        audioArray ? (NSObject*)                          audioArray:[NSNull null], @"audio",
        nil];

    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:modes options:0 error:nil];
    NSString* jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    NSString* jsString = [NSString stringWithFormat:@"navigator.device.capture.setSupportedModes(%@);", jsonStr];
    [self.commandDelegate evalJs:jsString];
}

- (void)getFormatData:(CDVInvokedUrlCommand*)command
{
    NSString* callbackId = command.callbackId;
    // existence of fullPath checked on JS side
    NSString* fullPath = [command argumentAtIndex:0];
    // mimeType could be null
    NSString* mimeType = nil;

    if ([command.arguments count] > 1) {
        mimeType = [command argumentAtIndex:1];
    }
    BOOL bError = NO;
    CDVCaptureError errorCode = CAPTURE_INTERNAL_ERR;
    CDVPluginResult* result = nil;

    if (!mimeType || [mimeType isKindOfClass:[NSNull class]]) {
        // try to determine mime type if not provided
        id command = [self.commandDelegate getCommandInstance:@"File"];
        bError = !([command isKindOfClass:[CDVFileBD class]]);
        if (!bError) {
            CDVFileBD* cdvFile = (CDVFileBD*)command;
            mimeType = [cdvFile getMimeTypeFromPath:fullPath];
            if (!mimeType) {
                // can't do much without mimeType, return error
                bError = YES;
                errorCode = CAPTURE_INVALID_ARGUMENT;
            }
        }
    }
    if (!bError) {
        // create and initialize return dictionary
        NSMutableDictionary* formatData = [NSMutableDictionary dictionaryWithCapacity:5];
        [formatData setObject:[NSNull null] forKey:kW3CMediaFormatCodecs];
        [formatData setObject:[NSNumber numberWithInt:0] forKey:kW3CMediaFormatBitrate];
        [formatData setObject:[NSNumber numberWithInt:0] forKey:kW3CMediaFormatHeight];
        [formatData setObject:[NSNumber numberWithInt:0] forKey:kW3CMediaFormatWidth];
        [formatData setObject:[NSNumber numberWithInt:0] forKey:kW3CMediaFormatDuration];

        if ([mimeType rangeOfString:@"image/"].location != NSNotFound) {
            UIImage* image = [UIImage imageWithContentsOfFile:fullPath];
            if (image) {
                CGSize imgSize = [image size];
                [formatData setObject:[NSNumber numberWithInteger:imgSize.width] forKey:kW3CMediaFormatWidth];
                [formatData setObject:[NSNumber numberWithInteger:imgSize.height] forKey:kW3CMediaFormatHeight];
            }
        } else if (([mimeType rangeOfString:@"video/"].location != NSNotFound) && (NSClassFromString(@"AVURLAsset") != nil)) {
            NSURL* movieURL = [NSURL fileURLWithPath:fullPath];
            AVURLAsset* movieAsset = [[AVURLAsset alloc] initWithURL:movieURL options:nil];
            CMTime duration = [movieAsset duration];
            [formatData setObject:[NSNumber numberWithFloat:CMTimeGetSeconds(duration)]  forKey:kW3CMediaFormatDuration];

            NSArray* allVideoTracks = [movieAsset tracksWithMediaType:AVMediaTypeVideo];
            if ([allVideoTracks count] > 0) {
                AVAssetTrack* track = [[movieAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
                CGSize size = [track naturalSize];

                [formatData setObject:[NSNumber numberWithFloat:size.height] forKey:kW3CMediaFormatHeight];
                [formatData setObject:[NSNumber numberWithFloat:size.width] forKey:kW3CMediaFormatWidth];
                // not sure how to get codecs or bitrate???
                // AVMetadataItem
                // AudioFile
            } else {
                NSLog(@"No video tracks found for %@", fullPath);
            }
        } else if ([mimeType rangeOfString:@"audio/"].location != NSNotFound) {
            if (NSClassFromString(@"AVAudioPlayer") != nil) {
                NSURL* fileURL = [NSURL fileURLWithPath:fullPath];
                NSError* err = nil;

                AVAudioPlayer* avPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL error:&err];
                if (!err) {
                    // get the data
                    [formatData setObject:[NSNumber numberWithDouble:[avPlayer duration]] forKey:kW3CMediaFormatDuration];
                    if ([avPlayer respondsToSelector:@selector(settings)]) {
                        NSDictionary* info = [avPlayer settings];
                        NSNumber* bitRate = [info objectForKey:AVEncoderBitRateKey];
                        if (bitRate) {
                            [formatData setObject:bitRate forKey:kW3CMediaFormatBitrate];
                        }
                    }
                } // else leave data init'ed to 0
            }
        }
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:formatData];
        // NSLog(@"getFormatData: %@", [formatData description]);
    }
    if (bError) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:(int)errorCode];
    }
    if (result) {
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }
}

- (NSDictionary*)getMediaDictionaryFromPath:(NSString*)fullPath ofType:(NSString*)type
{
    GDFileManager* fileMgr = [[GDFileManager alloc] init];
    NSMutableDictionary* fileDict = [NSMutableDictionary dictionaryWithCapacity:5];

    CDVFileBD *fs = [self.commandDelegate getCommandInstance:@"File"];

    // Get canonical version of localPath
    NSURL *fileURL = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", fullPath]];
    NSURL *resolvedFileURL = [fileURL URLByResolvingSymlinksInPath];
    NSString *path = [resolvedFileURL path];

    CDVFilesystemURLBD *url = [fs fileSystemURLforLocalPath:path];

    [fileDict setObject:[fullPath lastPathComponent] forKey:@"name"];
    [fileDict setObject:fullPath forKey:@"fullPath"];
    if (url) {
        [fileDict setObject:[url absoluteURL] forKey:@"localURL"];
    }
    // determine type
    if (!type) {
        id command = [self.commandDelegate getCommandInstance:@"File"];
        if ([command isKindOfClass:[CDVFileBD class]]) {
            CDVFileBD* cdvFile = (CDVFileBD*)command;
            NSString* mimeType = [cdvFile getMimeTypeFromPath:fullPath];
            [fileDict setObject:(mimeType != nil ? (NSObject*)mimeType : [NSNull null]) forKey:@"type"];
        }
    }
    NSDictionary* fileAttrs = [fileMgr attributesOfItemAtPath:fullPath error:nil];
    [fileDict setObject:[NSNumber numberWithUnsignedLongLong:[fileAttrs fileSize]] forKey:@"size"];
    NSDate* modDate = [fileAttrs fileModificationDate];
    NSNumber* msDate = [NSNumber numberWithDouble:[modDate timeIntervalSince1970] * 1000];
    [fileDict setObject:msDate forKey:@"lastModifiedDate"];

    return fileDict;
}

- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingImage:(UIImage*)image editingInfo:(NSDictionary*)editingInfo
{
    // older api calls new one
    [self imagePickerController:picker didFinishPickingMediaWithInfo:editingInfo];
}

/* Called when image/movie is finished recording.
 * Calls success or error code as appropriate
 * if successful, result  contains an array (with just one entry since can only get one image unless build own camera UI) of MediaFile object representing the image
 *      name
 *      fullPath
 *      type
 *      lastModifiedDate
 *      size
 */
- (void)imagePickerController:(UIImagePickerController*)picker didFinishPickingMediaWithInfo:(NSDictionary*)info
{
    CDVImagePickerBD* cameraPicker = (CDVImagePickerBD*)picker;
    NSString* callbackId = cameraPicker.callbackId;

    [[picker presentingViewController] dismissViewControllerAnimated:YES completion:nil];

    CDVPluginResult* result = nil;

    UIImage* image = nil;
    NSString* mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    if (!mediaType || [mediaType isEqualToString:(NSString*)kUTTypeImage]) {
        // mediaType is nil then only option is UIImagePickerControllerOriginalImage
        if ([UIImagePickerController respondsToSelector:@selector(allowsEditing)] &&
            (cameraPicker.allowsEditing && [info objectForKey:UIImagePickerControllerEditedImage])) {
            image = [info objectForKey:UIImagePickerControllerEditedImage];
        } else {
            image = [info objectForKey:UIImagePickerControllerOriginalImage];
        }
    }
    if (image != nil) {
        // mediaType was image
        result = [self processImage:image type:cameraPicker.mimeType forCallbackId:callbackId];
    } else if ([mediaType isEqualToString:(NSString*)kUTTypeMovie]) {
        // process video
        NSString* moviePath = [(NSURL *)[info objectForKey:UIImagePickerControllerMediaURL] path];
        if (moviePath) {
            result = [self processVideo:moviePath forCallbackId:callbackId];
        }
    }
    if (!result) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:CAPTURE_INTERNAL_ERR];
    }
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    pickerController = nil;
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker
{
    CDVImagePickerBD* cameraPicker = (CDVImagePickerBD*)picker;
    NSString* callbackId = cameraPicker.callbackId;

    [[picker presentingViewController] dismissViewControllerAnimated:YES completion:nil];

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:CAPTURE_NO_MEDIA_FILES];
    [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    pickerController = nil;
}

@end

@implementation CDVAudioNavigationControllerBD

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    // delegate to CVDAudioRecorderViewController
    return [self.topViewController supportedInterfaceOrientations];
}

@end

@interface CDVAudioRecorderViewControllerBD () {
    UIStatusBarStyle _previousStatusBarStyle;
}
@end

@implementation CDVAudioRecorderViewControllerBD
@synthesize errorCode, callbackId, duration, captureCommand, doneButton, recordingView, recordButton, recordImage, stopRecordImage, timerLabel, avRecorder, avSession, pluginResult, timer, isTimed;

- (NSString*)resolveImageResource:(NSString*)resource
{
    NSString* systemVersion = [[UIDevice currentDevice] systemVersion];
    BOOL isLessThaniOS4 = ([systemVersion compare:@"4.0" options:NSNumericSearch] == NSOrderedAscending);

    // the iPad image (nor retina) differentiation code was not in 3.x, and we have to explicitly set the path
    // if user wants iPhone only app to run on iPad they must remove *~ipad.* images from CDVCaptureBD.bundle
    if (isLessThaniOS4) {
        NSString* iPadResource = [NSString stringWithFormat:@"%@~ipad.png", resource];
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad && [UIImage imageNamed:iPadResource]) {
            return iPadResource;
        } else {
            return [NSString stringWithFormat:@"%@.png", resource];
        }
    }

    return resource;
}

- (id)initWithCommand:(CDVCaptureBD*)theCommand duration:(NSNumber*)theDuration callbackId:(NSString*)theCallbackId
{
    if ((self = [super init])) {
        self.captureCommand = theCommand;
        self.duration = theDuration;
        self.callbackId = theCallbackId;
        self.errorCode = CAPTURE_NO_MEDIA_FILES;
        self.isTimed = self.duration != nil;
        _previousStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;

        return self;
    }

    return nil;
}

- (void)loadView
{
	if ([self respondsToSelector:@selector(edgesForExtendedLayout)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    // create view and display
    CGRect viewRect = [[UIScreen mainScreen] bounds];
    UIView* tmp = [[UIView alloc] initWithFrame:viewRect];

    // make backgrounds
    NSString* microphoneResource = @"CDVCaptureBD.bundle/microphone";

    BOOL isIphone5 = ([[UIScreen mainScreen] bounds].size.width == 568 && [[UIScreen mainScreen] bounds].size.height == 320) || ([[UIScreen mainScreen] bounds].size.height == 568 && [[UIScreen mainScreen] bounds].size.width == 320);
    if (isIphone5) {
        microphoneResource = @"CDVCaptureBD.bundle/microphone-568h";
    }

    NSBundle* cdvBundle = [NSBundle bundleForClass:[CDVCaptureBD class]];
    UIImage* microphone = [UIImage imageNamed:[self resolveImageResource:microphoneResource] inBundle:cdvBundle compatibleWithTraitCollection:nil];
    UIView* microphoneView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, viewRect.size.width, microphone.size.height)];
    [microphoneView setBackgroundColor:[UIColor colorWithPatternImage:microphone]];
    [microphoneView setUserInteractionEnabled:NO];
    [microphoneView setIsAccessibilityElement:NO];
    [tmp addSubview:microphoneView];

    // add bottom bar view
    UIImage* grayBkg = [UIImage imageNamed:[self resolveImageResource:@"CDVCaptureBD.bundle/controls_bg"] inBundle:cdvBundle compatibleWithTraitCollection:nil];
    UIView* controls = [[UIView alloc] initWithFrame:CGRectMake(0, microphone.size.height, viewRect.size.width, grayBkg.size.height)];
    [controls setBackgroundColor:[UIColor colorWithPatternImage:grayBkg]];
    [controls setUserInteractionEnabled:NO];
    [controls setIsAccessibilityElement:NO];
    [tmp addSubview:controls];

    // make red recording background view
    UIImage* recordingBkg = [UIImage imageNamed:[self resolveImageResource:@"CDVCaptureBD.bundle/recording_bg"] inBundle:cdvBundle compatibleWithTraitCollection:nil];
    UIColor* background = [UIColor colorWithPatternImage:recordingBkg];
    self.recordingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, viewRect.size.width, recordingBkg.size.height)];
    [self.recordingView setBackgroundColor:background];
    [self.recordingView setHidden:YES];
    [self.recordingView setUserInteractionEnabled:NO];
    [self.recordingView setIsAccessibilityElement:NO];
    [tmp addSubview:self.recordingView];

    // add label
    self.timerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, viewRect.size.width, recordingBkg.size.height)];
    // timerLabel.autoresizingMask = reSizeMask;
    [self.timerLabel setBackgroundColor:[UIColor clearColor]];
    [self.timerLabel setTextColor:[UIColor whiteColor]];
    [self.timerLabel setTextAlignment:NSTextAlignmentCenter];
    [self.timerLabel setText:@"0:00"];
    [self.timerLabel setAccessibilityHint:PluginLocalizedString(captureCommand, @"recorded time in minutes and seconds", nil)];
    self.timerLabel.accessibilityTraits |= UIAccessibilityTraitUpdatesFrequently;
    self.timerLabel.accessibilityTraits &= ~UIAccessibilityTraitStaticText;
    [tmp addSubview:self.timerLabel];

    // Add record button

    self.recordImage = [UIImage imageNamed:[self resolveImageResource:@"CDVCaptureBD.bundle/record_button"] inBundle:cdvBundle compatibleWithTraitCollection:nil];
    self.stopRecordImage = [UIImage imageNamed:[self resolveImageResource:@"CDVCaptureBD.bundle/stop_button"] inBundle:cdvBundle compatibleWithTraitCollection:nil];
    self.recordButton.accessibilityTraits |= [self accessibilityTraits];
    self.recordButton = [[UIButton alloc] initWithFrame:CGRectMake((viewRect.size.width - recordImage.size.width) / 2, (microphone.size.height + (grayBkg.size.height - recordImage.size.height) / 2), recordImage.size.width, recordImage.size.height)];
    [self.recordButton setAccessibilityLabel:PluginLocalizedString(captureCommand, @"toggle audio recording", nil)];
    [self.recordButton setImage:recordImage forState:UIControlStateNormal];
    [self.recordButton addTarget:self action:@selector(processButton:) forControlEvents:UIControlEventTouchUpInside];
    [tmp addSubview:recordButton];

    // make and add done button to navigation bar
    self.doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissAudioView:)];
    [self.doneButton setStyle:UIBarButtonItemStyleDone];
    self.navigationItem.rightBarButtonItem = self.doneButton;

    [self setView:tmp];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
    NSError* error = nil;

    if (self.avSession == nil) {
        // create audio session
        self.avSession = [AVAudioSession sharedInstance];
        if (error) {
            // return error if can't create recording audio session
            NSLog(@"error creating audio session: %@", [[error userInfo] description]);
            self.errorCode = CAPTURE_INTERNAL_ERR;
            [self dismissAudioView:nil];
        }
    }

    [self.avSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];

    NSString* docsPath = [NSTemporaryDirectory()stringByStandardizingPath];   // use file system temporary directory
    NSError* err = nil;
    GDFileManager* fileMgr = [[GDFileManager alloc] init];

    // generate unique file name
    NSString* filePath;
    NSString* securedFilePath;
    int i = 1;
    do {
        filePath = [NSString stringWithFormat:@"%@/audio_%03d.wav", docsPath, i];
        securedFilePath = [MediaStorageHelper audioPath:[NSString stringWithFormat:@"audio_%03d.wav", i]];
        i++;
    } while ([fileMgr fileExistsAtPath:securedFilePath]);

    NSURL* fileURL = [NSURL fileURLWithPath:filePath isDirectory:NO];

    // create AVAudioPlayer
    NSDictionary *recordSetting = [[NSMutableDictionary alloc] init];
    self.avRecorder = [[AVAudioRecorder alloc] initWithURL:fileURL settings:recordSetting error:&err];
    if (err) {
        NSLog(@"Failed to initialize AVAudioRecorder: %@\n", [err localizedDescription]);
        self.avRecorder = nil;
        // return error
        self.errorCode = CAPTURE_INTERNAL_ERR;
        [self dismissAudioView:nil];
    } else {
        self.avRecorder.delegate = self;
        [self.avRecorder prepareToRecord];
        self.recordButton.enabled = YES;
        self.doneButton.enabled = YES;
    }
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    UIInterfaceOrientationMask orientation = UIInterfaceOrientationMaskPortrait;
    UIInterfaceOrientationMask supported = [captureCommand.viewController supportedInterfaceOrientations];

    orientation = orientation | (supported & UIInterfaceOrientationMaskPortraitUpsideDown);
    return orientation;
}

- (void)processButton:(id)sender
{
    if (self.avRecorder.recording) {
        // stop recording
        [self.avRecorder stop];
        self.isTimed = NO;  // recording was stopped via button so reset isTimed
        // view cleanup will occur in audioRecordingDidFinishRecording
    } else {
        // begin recording
        [self.recordButton setImage:stopRecordImage forState:UIControlStateNormal];
        self.recordButton.accessibilityTraits &= ~[self accessibilityTraits];
        [self.recordingView setHidden:NO];
        __block NSError* error = nil;

        __weak CDVAudioRecorderViewControllerBD* weakSelf = self;

        void (^startRecording)(void) = ^{
            [weakSelf.avSession setActive:YES error:&error];
            if (error) {
                // can't continue without active audio session
                weakSelf.errorCode = CAPTURE_INTERNAL_ERR;
                [weakSelf dismissAudioView:nil];
            } else {
                if (weakSelf.duration) {
                    weakSelf.isTimed = true;
                    [weakSelf.avRecorder recordForDuration:[weakSelf.duration doubleValue]];
                } else {
                    [weakSelf.avRecorder record];
                }
                [weakSelf.timerLabel setText:@"0.00"];
                weakSelf.timer = [NSTimer scheduledTimerWithTimeInterval:0.5f target:weakSelf selector:@selector(updateTime) userInfo:nil repeats:YES];
                weakSelf.doneButton.enabled = NO;
            }
            UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
        };

        SEL rrpSel = NSSelectorFromString(@"requestRecordPermission:");
        if ([self.avSession respondsToSelector:rrpSel])
        {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [self.avSession performSelector:rrpSel withObject:^(BOOL granted){
                if (granted) {
                    startRecording();
                } else {
                    NSLog(@"Error creating audio session, microphone permission denied.");
                    weakSelf.errorCode = CAPTURE_INTERNAL_ERR;
                    [weakSelf dismissAudioView:nil];
                }
            }];
#pragma clang diagnostic pop
        } else {
            startRecording();
        }
    }
}

/*
 * helper method to clean up when stop recording
 */
- (void)stopRecordingCleanup
{
    if (self.avRecorder.recording) {
        [self.avRecorder stop];
    }
    [self.recordButton setImage:recordImage forState:UIControlStateNormal];
    self.recordButton.accessibilityTraits |= [self accessibilityTraits];
    [self.recordingView setHidden:YES];
    self.doneButton.enabled = YES;
    if (self.avSession) {
        // deactivate session so sounds can come through
        [self.avSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
        [self.avSession setActive:NO error:nil];
    }
    if (self.duration && self.isTimed) {
        // VoiceOver announcement so user knows timed recording has finished
        //BOOL isUIAccessibilityAnnouncementNotification = (&UIAccessibilityAnnouncementNotification != NULL);
        if (UIAccessibilityAnnouncementNotification) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500ull * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, PluginLocalizedString(self->captureCommand, @"timed recording complete", nil));
                });
        }
    } else {
        // issue a layout notification change so that VO will reannounce the button label when recording completes
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
    }
}

- (void)dismissAudioView:(id)sender
{
    // called when done button pressed or when error condition to do cleanup and remove view
    [[self.captureCommand.viewController.presentedViewController presentingViewController] dismissViewControllerAnimated:YES completion:nil];

    if (!self.pluginResult) {
        // return error
        self.pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:(int)self.errorCode];
    }

    self.avRecorder = nil;
    [self.avSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [self.avSession setActive:NO error:nil];
    [self.captureCommand setInUse:NO];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
    // return result
    [self.captureCommand.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void)updateTime
{
    // update the label with the elapsed time
    [self.timerLabel setText:[self formatTime:self.avRecorder.currentTime]];
}

- (NSString*)formatTime:(int)interval
{
    // is this format universal?
    int secs = interval % 60;
    int min = interval / 60;

    if (interval < 60) {
        return [NSString stringWithFormat:@"0:%02d", interval];
    } else {
        return [NSString stringWithFormat:@"%d:%02d", min, secs];
    }
}

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder*)recorder successfully:(BOOL)flag
{
    // may be called when timed audio finishes - need to stop time and reset buttons
    [self.timer invalidate];
    [self stopRecordingCleanup];

    // generate success result
    if (flag) {
        NSString* filePath = [avRecorder.url path];
        NSDictionary* fileDict = [captureCommand getMediaDictionaryFromPath:filePath ofType:@"audio/wav"];
        NSArray* fileArray = [NSArray arrayWithObject:fileDict];

        @try {
            NSError* error;
            NSString* audioName = [filePath lastPathComponent];
            NSString* securePath = [MediaStorageHelper audioPath:audioName];

            [MediaStorageHelper copyItemAtPath:filePath toSecurePath:securePath];

            [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
        } @catch (NSException *exception) {
            self.pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageToErrorObject:CAPTURE_INTERNAL_ERR];
        }

        self.pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:fileArray];
    } else {
        self.pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageToErrorObject:CAPTURE_INTERNAL_ERR];
    }
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder*)recorder error:(NSError*)error
{
    [self.timer invalidate];
    [self stopRecordingCleanup];

    NSLog(@"error recording audio");
    self.pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageToErrorObject:CAPTURE_INTERNAL_ERR];
    [self dismissAudioView:nil];
}

@end