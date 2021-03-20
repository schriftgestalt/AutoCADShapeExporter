//
//  AutoCADShapeExporter.h
//  AutoCADShapeExporter
//
//  Created by Georg Seifert on 20.01.16.
//  Copyright © 2016 Georg Seifert. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <GlyphsCore/GlyphsFileFormatProtocol.h>

@class GSFont;
@class GSProgressWindow;

@interface AutoCADShapeExporter : NSViewController <GlyphsFileFormat> {
	NSImage *_toolbarIcon;
}

@property(nonatomic, readonly) GSProgressWindow *progressWindow;

@end
