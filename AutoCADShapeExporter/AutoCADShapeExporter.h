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

@interface AutoCADShapeExporter : NSObject <GlyphsFileFormat> {
	NSImage *_toolbarIcon;
	NSView *_exportSettingsView;
	GSFont __unsafe_unretained *_font;
}

@property(nonatomic, readonly) GSProgressWindow *progressWindow;
@property(nonatomic) IBOutlet NSView *exportSettingsView;
@end
