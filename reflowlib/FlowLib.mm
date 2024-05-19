//
//  djvulibre.m
//  djvulibre
//
//  Created by Sergey Mikhno on 25.08.18.
//  Copyright © 2018 Sergey Mikhno. All rights reserved.
//  Copyright © 2018 Sergey Mikhno. All rights reserved.
//

#define OPENCV_TRAITS_ENABLE_DEPRECATED

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>


#import "FlowLib.h"
#include "Enclosure.h"
#include "PageSegmenter.h"
#include "Reflow.h"
#include "ddjvuapi.h"
#include <iostream>
#include <tuple>
#include <vector>
#include <map>
#include <vector>
#include <algorithm>
#include <array>
#include <set>
#include <limits>
#include <string>
#include <numeric>
#include <stack>
#include <cstdlib>
#include <cmath>
#include "allheaders.h"

using namespace std;

bool getSortedPointsFromCache(vector<std::array<int,4>>& _newPoints, int pageNumber, NSManagedObjectContext* context) {
    bool pageFound = false;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"ManagedMat"];
    request.predicate =  [NSPredicate predicateWithFormat:(@"pageNo == %d"), pageNumber];
    //[request setPredicate: [NSPredicate predicateWithFormat:(@"pageNo == %@"), pageNumber]];
    
    
    NSError *e = nil;
    NSArray *results = [context executeFetchRequest:request error:&e];
    
    if ([results count] > 0) {
        pageFound = true;
        ManagedMat* managedMat = results.firstObject;
        //NSData* data = managedMat.data;
        //NSArray *array = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        /*
         std::stack<int> stack;
         int i = 0;
         for (id object in array) {
         
         if([object isKindOfClass:[NSNumber class]]) {
         int intVal = [object intValue];
         stack.push(intVal);
         }
         i++;
         if (i % 4 == 0) {
         i = 0;
         std::array<int,4> arr;
         int j = 4;
         while (j > 0) {
         int k = stack.top();
         arr[j-1] = k;
         stack.pop();
         j--;
         }
         _newPoints.push_back(arr);
         }
         
         }
         */
        
    }
    return pageFound;
}

void handleMessages(ddjvu_context_t *ctx) {
    const ddjvu_message_t *msg;
    while ((msg = ddjvu_message_peek(ctx))) {
        switch (msg->m_any.tag) {
            case DDJVU_ERROR:
                break;
            case DDJVU_INFO:
                break;
            case DDJVU_DOCINFO:
                break;
            default:
                break;
        }
        ddjvu_message_pop(ctx);
    }
}

void waitAndHandleMessages(ddjvu_context_t *contextHandle) {
    ddjvu_context_t *ctx = contextHandle;
    // Wait for first message
    ddjvu_message_wait(ctx);
    // Process available messages
    handleMessages(ctx);
}

char* getPdfPage(const char *str, int pageNumber, cv::Mat& cvMat, int& h, int& w) {
    CFStringRef path = CFStringCreateWithCString(NULL, str, kCFStringEncodingUTF8);
  
    CFURLRef url;
    CGPDFPageRef page;
    url = CFURLCreateWithFileSystemPath (NULL, path, // 1
                                         kCFURLPOSIXPathStyle, 0);
    
  
    CGPDFDocumentRef document;
    
    document = CGPDFDocumentCreateWithURL (url);
    page = CGPDFDocumentGetPage (document, pageNumber+1);
    CFRelease(url);
    
    float dpi = 300.0 / 72.0;
    
    CGRect bounds = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    w = (int)CGRectGetWidth(bounds) * dpi;
    h = (int)CGRectGetHeight(bounds) * dpi;
    

    CGBitmapInfo info = kCGBitmapByteOrder32Big | kCGImageAlphaNoneSkipLast;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    

    std::unique_ptr<uint32_t[]> bitmap(new uint32_t[w * h]);
    memset(bitmap.get(), 0xFF, 4 * w * h);
    
    CGContextRef ctx = CGBitmapContextCreate(bitmap.get(), w, h, 8, w*4, cs, info);
    
    
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextScaleCTM(ctx, dpi, dpi);
    CGContextSaveGState(ctx);
    
    CGContextDrawPDFPage(ctx, page);
    CGContextRestoreGState(ctx);
    
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    
    CGColorSpaceRelease(cs);
    CGImageRelease(image);
    CGContextRelease(ctx);
    CGPDFDocumentRelease(document);
    cvMat = cv::Mat(h, w, CV_8UC(4), (char*)bitmap.get());
    return (char*)bitmap.get();
  
    
}


char* getDjvuPage(const char *str, int pageNumber, cv::Mat& cvMat, bool colored, int& h, int& w) {
    ddjvu_context_t *ctx = ddjvu_context_create("djvu");
    
    ddjvu_document_t *doc = ddjvu_document_create_by_filename(ctx, str, TRUE);
    
    ddjvu_page_t *page= ddjvu_page_create_by_pageno(doc, pageNumber);
    
    while (!ddjvu_page_decoding_done (page )) {
    }
    
    ddjvu_status_t r;
    ddjvu_pageinfo_t info;
    while ((r=ddjvu_document_get_pageinfo(doc,pageNumber,&info))<DDJVU_JOB_OK) {
        
    }
    
    w = info.width;
    h = info.height;
    
    unsigned int masks[] = {0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000};
    ddjvu_format_t *format = colored ? ddjvu_format_create(DDJVU_FORMAT_RGBMASK32, 4, masks) : ddjvu_format_create(DDJVU_FORMAT_GREY8, 0, NULL);
    
    
    ddjvu_format_set_row_order(format, 1);
    ddjvu_format_set_y_direction(format, 1);
    
    int size = colored ? w * h * 4 : w * h;
    char *pixels = (char*)malloc(size);
    
    while (!ddjvu_page_decoding_done(page)) {
        waitAndHandleMessages(ctx);
    }
    
    ddjvu_rect_t rrect;
    ddjvu_rect_t prect;
    
    prect.x = 0;
    prect.y = 0;
    prect.w = w;
    prect.h = h;
    rrect = prect;
    
    int strade = colored ? w * 4 : w;
    ddjvu_page_render (page, DDJVU_RENDER_COLOR,
                       &prect,
                       &rrect,
                       format,
                       strade,
                       pixels);
    
    
    ddjvu_format_release(format);
    //ddjvu_page_release(page);
    
    cvMat = colored ? cv::Mat(h, w, CV_8UC(4), pixels) : cv::Mat(h, w, CV_8UC(1), pixels);
    return pixels;
}


void saveToCache(vector<std::array<int,4>>& _newPoints, int pageNumber, NSManagedObjectContext* context) {
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"ManagedMat"];
    request.predicate =  [NSPredicate predicateWithFormat:(@"pageNo == %d"), pageNumber];
    
    NSError *e = nil;
    NSArray *results = [context executeFetchRequest:request error:&e];
    
    if ([results count] == 0) {
        unsigned long arraySize = _newPoints.size() * 4;
        NSMutableArray * myArray = [NSMutableArray arrayWithCapacity:arraySize];
        
        for(int i=0;i<_newPoints.size(); i++) {
            array<int,4> p = _newPoints[i];
            int a = get<0>(p);
            [myArray addObject:[NSNumber numberWithInt:a]];
            a = get<1>(p);
            [myArray addObject:[NSNumber numberWithInt:a]];
            a = get<2>(p);
            [myArray addObject:[NSNumber numberWithInt:a]];
            a = get<3>(p);
            [myArray addObject:[NSNumber numberWithInt:a]];
        }
        
        NSData *arrayData = [NSKeyedArchiver archivedDataWithRootObject:myArray];
        
        ManagedMat *managedMat = [NSEntityDescription insertNewObjectForEntityForName:@"ManagedMat" inManagedObjectContext:context];
        //managedMat.data = arrayData;
        managedMat.pageNo = pageNumber;
    }
    
}

UIImage* createFinalImage(cv::Mat& blankImage, NSData *data, CGBitmapInfo bitmapInfo) {
    CGColorSpaceRef colorSpace;
    
    if (blankImage.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
    
    //colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    // Creating CGImage from cv::Mat
    
    CGImageRef imageRef = CGImageCreate(blankImage.cols,                                 //width
                                        blankImage.rows,                                 //height
                                        8,                                          //bits per component
                                        8 * blankImage.elemSize(),                       //bits per pixel
                                        blankImage.step[0],                            //bytesPerRow
                                        colorSpace,                                 //colorspace
                                        bitmapInfo,// bitmap info
                                        provider,                                   //CGDataProviderRef
                                        NULL,                                       //decode
                                        false,                                      //should interpolate
                                        kCGRenderingIntentDefault                   //intent
                                        
                                        );
    
    UIImage *finalImage = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    return finalImage;
}

@implementation ManagedMat

//@dynamic data;
@dynamic pageNo;
@dynamic filename;
@end


@implementation FlowLib

+(NSString*)djvuVersion {
    NSString* s = [NSString stringWithFormat:@"djvulibre Version %d",  DDJVUAPI_VERSION];
    return s;
}

+(int)getNumberOfPages:(NSString*)filePath {
    
    if ([filePath hasSuffix:@".pdf"]) {
        CFStringRef path = (__bridge CFStringRef)filePath;;
        CFURLRef url;
        url = CFURLCreateWithFileSystemPath (NULL, path, // 1
                                             kCFURLPOSIXPathStyle, 0);
        
        //CFRelease (path);
        CGPDFDocumentRef document;
        
        document = CGPDFDocumentCreateWithURL (url);
        int count = (int)CGPDFDocumentGetNumberOfPages(document);
        CGPDFDocumentRelease(document);
        CFRelease (url);
        return count;
        
    } else {
        ddjvu_context_t *ctx = ddjvu_context_create("djvu");
        const char *str = [filePath UTF8String];
        ddjvu_document_t *doc = ddjvu_document_create_by_filename(ctx, str, TRUE);
        
        ddjvu_message_wait(ctx);
        while (ddjvu_message_peek(ctx)) {
            if (ddjvu_document_decoding_done(doc)) {
                break;
            }
            ddjvu_message_pop(ctx);
        }
        
        return ddjvu_document_get_pagenum(doc);
    }
    
}


+(NSString*)getRecognizedPage:(NSString*)filePath for:(int)pageNumber withTessdata:(NSString*)tessdataPath withContext:(NSManagedObjectContext*)context withLang:(NSString*)lang {
    
    const char *strLang = [lang UTF8String];
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"ManagedMat"];
    
    NSString* theFileName = [filePath lastPathComponent];
    request.predicate =  [NSPredicate predicateWithFormat:(@"filename == %@"), theFileName];
    
    NSError *e = nil;
    NSArray *results = [context executeFetchRequest:request error:&e];
    
    if ([results count] > 0) {
        
        ManagedMat* managedMat = results.firstObject;
        managedMat.pageNo = pageNumber;
        [context save:&e];
    }
    if ([filePath hasSuffix:@".djvu"]) {
        
        cv::Mat cvMat;
        int h;
        int w;
        const char *str = [filePath UTF8String];
        
        char* pixels = getDjvuPage(str, pageNumber, cvMat, false, h, w);
        
        threshold(cvMat, cvMat, 0, 255, cv::THRESH_BINARY_INV | cv::THRESH_OTSU);
        cv::Mat rotated_with_pictures;
        std::vector<glyph> pic_glyphs = preprocess(cvMat, rotated_with_pictures);
        cv::Mat new_image;
        //remove_skew(cvMat);
        
        tesseract::TessBaseAPI *api = new tesseract::TessBaseAPI();
        const char *tessData = [tessdataPath UTF8String];
        
       
        int a = 1;
        a = a + 1;
        
        NSLog(@"testing");
        
        
        if (api->Init(tessData, strLang)) {
            fprintf(stderr, "Could not initialize tesseract.\n");
            free(pixels);
            return [NSString stringWithUTF8String:""];
        } else {
            api->SetSourceResolution(72);
            api->SetImage((const unsigned char*)cvMat.data, w, h, 1, w);
            char* outText = api->GetUTF8Text();
            printf("OCR output:\n%s", outText);
            free(pixels);
            return [NSString stringWithUTF8String:outText];
            
        }
        
        
    }
    else if ([filePath hasSuffix:@".pdf"]) {
        cv::Mat cvMat;
        int h;
        int w;
        const char *str = NULL; //[filePath UTF8String];
        
        char* pixels = getPdfPage(str, pageNumber, cvMat, h, w);
        
        threshold(cvMat, cvMat, 0, 255, cv::THRESH_BINARY_INV | cv::THRESH_OTSU);
        cv::Mat rotated_with_pictures;
        std::vector<glyph> pic_glyphs = preprocess(cvMat, rotated_with_pictures);
        cv::Mat new_image;
        //remove_skew(cvMat);
        
        tesseract::TessBaseAPI *api = new tesseract::TessBaseAPI();
        const char *tessData = [tessdataPath UTF8String];
        
        if (api->Init(tessData, strLang)) {
            fprintf(stderr, "Could not initialize tesseract.\n");
            free(pixels);
            return [NSString stringWithUTF8String:""];
        } else {
            api->SetImage((const unsigned char*)cvMat.data, w, h, 1, w);
            char* outText = api->GetUTF8Text();
            printf("OCR output:\n%s", outText);
            free(pixels);
            return [NSString stringWithUTF8String:outText];
            
        }
        
    }

    
    return [NSString stringWithUTF8String:""];
    
    
    
}

UIImage *GetImageFromPix(Pix *thePix)
{
    UIImage *result = nil;
    
    l_uint8 *bytes = NULL;
    size_t size = 0;
    
    if (0 == pixWriteMem(&bytes, &size, thePix, IFF_TIFF)) {
        NSData *data = [[NSData alloc] initWithBytesNoCopy:bytes length:(NSUInteger)size freeWhenDone:YES];
        result = [UIImage imageWithData:data];
    }
    
    return result;
}

Pix *mat8ToPix(cv::Mat *mat8)
{
    Pix *pixd = pixCreate(mat8->size().width, mat8->size().height, 8);
    for(int y=0; y<mat8->rows; y++) {
        for(int x=0; x<mat8->cols; x++) {
            pixSetPixel(pixd, x, y, (l_uint32) mat8->at<uchar>(y,x));
        }
    }
    return pixd;
}

cv::Mat pix8ToMat(Pix *pix8)
{
    cv::Mat mat(cv::Size(pix8->w, pix8->h), CV_8UC1);
    uint32_t *line = pix8->data;
    for (uint32_t y = 0; y < pix8->h; ++y) {
        for (uint32_t x = 0; x < pix8->w; ++x) {
            mat.at<uchar>(y, x) = GET_DATA_BYTE(line, x);
        }
        line += pix8->wpl;
    }
    return mat;
}


+(UIImage*)getNewPage:(NSString*)filePath for:(int)pageNumber  withContext:(NSManagedObjectContext*)context  width:(int)pageWidth newScale:(CGFloat)scale flow:(bool)flow {
    
    int arr[5] = {10, 20, 30, 40, 50};
    int z = arr[10];
    
    return nil;
    
}


+(UIImage*)getPage:(NSString*)filePath for:(int)pageNumber  withContext:(NSManagedObjectContext*)context  width:(int)pageWidth newScale:(CGFloat)scale flow:(bool)flow {
    //NSURL *resourceToOpen = [NSURL fileURLWithPath:filePath];
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"ManagedMat"];
    
    NSString* theFileName = [filePath lastPathComponent];
    request.predicate =  [NSPredicate predicateWithFormat:(@"filename == %@"), theFileName];
    
    NSError *e = nil;
    NSArray *results = [context executeFetchRequest:request error:&e];
    
    if ([results count] > 0) {
        
        ManagedMat* managedMat = results.firstObject;
       managedMat.pageNo = pageNumber;
        [context save:&e];
    }
    
    float dpi = 300.0 / 72.0;
    
    if ([filePath hasSuffix:@".pdf"]) {
        CFStringRef path = (__bridge CFStringRef)filePath;;
        CFURLRef url;
        CGPDFPageRef page;
        url = CFURLCreateWithFileSystemPath (NULL, path, // 1
                                             kCFURLPOSIXPathStyle, 0);
        
        //CFRelease (path);
        CGPDFDocumentRef document;
        
        document = CGPDFDocumentCreateWithURL (url);
        page = CGPDFDocumentGetPage (document, pageNumber+1);
        CFRelease(url);
        
        
        
        CGRect bounds = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
        int w = (int)CGRectGetWidth(bounds) * dpi;
        int h = (int)CGRectGetHeight(bounds) * dpi;
        
        //CGRect rect = CGRectMake(0,0, w, h);
        
        //CGBitmapInfo info = kCGImageByteOrderDefault | kCGImageAlphaNone;
        CGBitmapInfo info = kCGBitmapByteOrder32Big | kCGImageAlphaNoneSkipLast;
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        
        //CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
        
        
        
        std::unique_ptr<uint32_t[]> bitmap(new uint32_t[w * h]);
        memset(bitmap.get(), 0xFF, 4 * w * h);
        
        CGContextRef ctx = CGBitmapContextCreate(bitmap.get(), w, h, 8, w*4, cs, info);
        
        //CGContextRef ctx = CGBitmapContextCreate(nil, w, h, 8, w, cs, info);
        //CGContextSetFillColor(ctx, CGColorGetComponents([UIColor whiteColor].CGColor));
        //CGContextClearRect(ctx, bounds);
        //CGContextFillRect(ctx, rect);
        
        CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
        //CGContextSetRenderingIntent(ctx, kCGRenderingIntentDefault);
        CGContextScaleCTM(ctx, dpi, dpi);
        CGContextSaveGState(ctx);
        //CGContextScaleCTM(ctx, 4.0, 4.0);
        
        CGContextDrawPDFPage(ctx, page);
        CGContextRestoreGState(ctx);
        
        CGImageRef image = CGBitmapContextCreateImage(ctx);
        
        
        if (!flow) {
            UIImage* im = [UIImage imageWithCGImage:image];
            CGColorSpaceRelease(cs);
            CGImageRelease(image);
            CGContextRelease(ctx);
            CGPDFDocumentRelease(document);
            return im;
        }
        
        cv::Mat cvMat = cv::Mat(h, w, CV_8UC(4), (char*)bitmap.get());
        cv::cvtColor(cvMat, cvMat, cv::COLOR_BGR2GRAY);
        
        std::vector<uchar> buff;//buffer for coding
        cv::imencode(".png", cvMat, buff);
        
        PIX* pix = pixReadMemPng((l_uint8*)&buff[0], buff.size()) ;
        PIX* result;
        dewarpSinglePage(pix, 127, 1, 0, 0, &result, NULL, 1);
        PIX* r = pixDeskew(result, 0);
        pixDestroy(&result);
       
        pixDestroy(&pix);
        
        
        //pixOtsuAdaptiveThreshold(r,pixGetWidth(r), pixGetHeight(r), 0,0,0.1,NULL,&outp);
        
        cv::Mat m = pix8ToMat(r);
        pixDestroy(&r);
        
       
        
        threshold(m, m, 0, 255, cv::THRESH_BINARY_INV | cv::THRESH_OTSU);
        
        
        cv:Mat rotated_with_pictures;
        std::vector<glyph> pic_glyphs = preprocess(m, rotated_with_pictures);
        
        cv::Mat new_image;// = cvMat;
        reflow(m, new_image, scale, pic_glyphs, rotated_with_pictures, pageWidth);
        //cvMat.release();
        
        
        NSData* data = [NSData dataWithBytes:new_image.data length:new_image.elemSize()*new_image.total()];
        CGBitmapInfo bitmapInfo = flow ? kCGImageAlphaNone|kCGBitmapByteOrderDefault : kCGImageAlphaNoneSkipLast|kCGBitmapByteOrderDefault;
        UIImage* im = createFinalImage(new_image, data, bitmapInfo);
        //new_image.release();
        
        CGImageRelease(image);
        CGColorSpaceRelease(cs);
        CGContextRelease(ctx);
        //CGPDFPageRelease(page);
        CGPDFDocumentRelease(document);
        
        //UIImage* img = [UIImage imageWithCGImage:image];
        //CGImageRelease(image);
        
        return im;
        
        
        
    } else if([filePath hasSuffix:@".djvu"]) {
        
        cv::Mat cvMat;
        int h;
        int w;
        const char *str = [filePath UTF8String];
        
        vector<std::array<int,4>> _newPoints;
        
        
        
        if (!flow) {
            char* pixels = getDjvuPage(str, pageNumber, cvMat, true, h, w);
            
            
            NSData *data = [NSData dataWithBytes:cvMat.data length:cvMat.elemSize()*cvMat.total()];
            CGBitmapInfo bitmapInfo = flow ? kCGImageAlphaNone|kCGBitmapByteOrderDefault : kCGImageAlphaNoneSkipLast|kCGBitmapByteOrderDefault;
            UIImage *image = createFinalImage(cvMat, data, bitmapInfo);
            free(pixels);
            
            return image;
        }
        char* pixels = getDjvuPage(str, pageNumber, cvMat, false, h, w);
        
        std::vector<uchar> buff;//buffer for coding
        cv::imencode(".png", cvMat, buff);
        
        PIX* pix = pixReadMemPng((l_uint8*)&buff[0], buff.size()) ;
        PIX* result;
        dewarpSinglePage(pix, 127, 1, 1, 1, &result, NULL, 1);
        PIX* r = pixDeskew(result, 0);
        pixDestroy(&result);
        pixDestroy(&pix);
        
        
        //pixOtsuAdaptiveThreshold(r,pixGetWidth(r), pixGetHeight(r), 0,0,0.1,NULL,&outp);
        
        
        cv::Mat m = pix8ToMat(r);
        
        threshold(m, m, 0, 255, cv::THRESH_BINARY_INV | cv::THRESH_OTSU);
        
        cv::Mat rotated_with_pictures;
        std::vector<glyph> pic_glyphs = preprocess(m, rotated_with_pictures);
        cv::Mat new_image;
        
        reflow(m, new_image, scale, pic_glyphs, rotated_with_pictures, pageWidth);
        NSData* data = [NSData dataWithBytes:new_image.data length:new_image.elemSize()*new_image.total()];
        CGBitmapInfo bitmapInfo = flow ? kCGImageAlphaNone|kCGBitmapByteOrderDefault : kCGImageAlphaNoneSkipLast|kCGBitmapByteOrderDefault;
        
        UIImage* im = createFinalImage(new_image, data, bitmapInfo);
        
        
        //NSData* data = [NSData dataWithBytes:m.data length:m.elemSize()*m.total()];
        
        
        //UIImage* img = createFinalImage(m, data);
        
        //UIImage* img =  GetImageFromPix(r);
        pixDestroy(&r);
        free(pixels);
        return im;
        
        /*
         threshold(cvMat, cvMat, 0, 255, cv::THRESH_BINARY_INV | cv::THRESH_OTSU);
         
         
         
         cv::Mat rotated_with_pictures;
         std::vector<glyph> pic_glyphs = preprocess(cvMat, rotated_with_pictures);
         cv::Mat new_image;
         //remove_skew(cvMat);
         
         reflow(cvMat, new_image, scale, pic_glyphs, rotated_with_pictures);
         NSData* data = [NSData dataWithBytes:new_image.data length:new_image.elemSize()*new_image.total()];
         UIImage* im = createFinalImage(new_image, data);
         
         //new_image.release();
         
         free(pixels);
         
         return im;
         */
        
    } else {
        UIImage* image = [UIImage imageWithContentsOfFile:filePath];
        
        if (!flow) {
            return image;
        }
        
        
        CGImageRef imageRef = [image CGImage];
        NSUInteger width = CGImageGetWidth(imageRef);
        NSUInteger height = CGImageGetHeight(imageRef);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        unsigned char *rawData = (unsigned char*) calloc(height * width * 4, sizeof(unsigned char));
        NSUInteger bytesPerPixel = 4;
        NSUInteger bytesPerRow = bytesPerPixel * width;
        NSUInteger bitsPerComponent = 8;
        CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                     bitsPerComponent, bytesPerRow, colorSpace,
                                                     kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(colorSpace);
        
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
        CGContextRelease(context);
        
        cv::Mat cvMat = cv::Mat((int)height, (int)width, CV_8UC(4), rawData);
        cv::cvtColor(cvMat, cvMat, cv::COLOR_BGR2GRAY);
        threshold(cvMat, cvMat, 0, 255, cv::THRESH_BINARY_INV | cv::THRESH_OTSU);
        cv::Mat new_image;
        reflow(cvMat, new_image, scale, std::vector<glyph>(), cvMat, pageWidth);
        cvMat.release();
        free(rawData);
        
        NSData *data = [NSData dataWithBytes:new_image.data length:new_image.elemSize()*new_image.total()];
        CGBitmapInfo bitmapInfo = flow ? kCGImageAlphaNone|kCGBitmapByteOrderDefault : kCGImageAlphaNoneSkipLast|kCGBitmapByteOrderDefault;
        UIImage *img = createFinalImage(new_image, data, bitmapInfo);
        new_image.release();
        return img;
    }
    
}




void reflow(cv::Mat& cvMat, cv::Mat& new_image, float scale, std::vector<glyph> pic_glyphs, cv::Mat& rotated_with_pictures, int page_width) {
    const cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(2, 1));
    
    //cv::morphologyEx(cvMat, cvMat, cv::MORPH_CLOSE, kernel);
    
    bool debug = false;
    
    cv::dilate(cvMat, cvMat, kernel, cv::Point(-1, -1), 1);
    std::vector<glyph> glyphs = get_glyphs(cvMat);
    
    std::vector<glyph> new_glyphs;
    
    for (glyph g : pic_glyphs) {
        int y = g.y;
        auto it = std::find_if(glyphs.begin(), glyphs.end(), [y] (const glyph& gl) {return gl.y > y;} );
        glyphs.insert(it, g);
    }
    
    
    
    if (debug) {
        for (int i=0;i<glyphs.size(); i++){
            glyph g = glyphs.at(i);
            cv::rectangle(cvMat, cv::Point(g.x, g.y), cv::Point(g.x + g.width, g.y + g.height), cv::Scalar(255), 5);
        }
    }
    
    
    if (!glyphs.empty()) {
        
        try {
            if (debug) {
                cv::bitwise_not(cvMat, cvMat);
                new_image = cvMat;
            } else {
                Reflow reflower(cvMat, rotated_with_pictures,  glyphs);
                new_image = reflower.reflow(scale, 1.0f, page_width);
            }
            
            
        }
        
        catch (...) {
            cv::bitwise_not(rotated_with_pictures, rotated_with_pictures);
            new_image = rotated_with_pictures;
        }
        
        //Reflow reflower(cvMat, rotated_with_pictures,  glyphs);
        //new_image = reflower.reflow(scale);
        //cv::bitwise_not(cvMat, cvMat);
        //new_image = cvMat;
        std::cout << "glyphs count " << glyphs.size() << std::endl;
        
    } else {
        cv::bitwise_not(cvMat, cvMat);
        new_image = cvMat;
    }
    
}



@end
