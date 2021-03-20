//
//  AutoCADShapeExporter.m
//  AutoCADShapeExporter
//
//  Created by Georg Seifert on 20.01.16.
//  Copyright © 2016 Georg Seifert. All rights reserved.
//

#import "AutoCADShapeExporter.h"
#import <GlyphsCore/GlyphsFilterProtocol.h>
#import <GlyphsCore/GSFont.h>
#import <GlyphsCore/GSFontMaster.h>
#import <GlyphsCore/GSInstance.h>
#import <GlyphsCore/GSGlyph.h>
#import <GlyphsCore/GSLayer.h>
#import <GlyphsCore/GSPath.h>
#import <GlyphsCore/GSNode.h>
#import <GlyphsCore/GSPenProtocol.h>
#import <GlyphsCore/GSGeometrieHelper.h>
#import <GlyphsCore/GSModalOpenPanel.h>

@interface AutoCadPen : NSObject <GSPenProtocol> {
	NSPoint _lastMovePoint;
	int _currentMode;
}

@property(nonatomic) NSUInteger byteCount;
@property(nonatomic) NSPoint lastPoint;
@property(nonatomic, strong) NSMutableString *string;
@end

@implementation AutoCadPen

- (void)setMode:(int)mode {
	if (mode != _currentMode) {
		[_string appendFormat:@",%d", mode];
		_currentMode = mode;
		_byteCount++;
	}
}

- (void)drawLine:(NSPoint)pt mode:(int)mode {
	NSPoint delta = GSSubtractPoints(pt, _lastPoint);
	if (fabs(delta.x) > 0.6 || fabs(delta.y) > 0.6) {
		[self setMode:mode];
		if (mode != _currentMode) {
			[_string appendFormat:@",%d", mode];
			_currentMode = mode;
			_byteCount++;
		}
		if (fabs(delta.x) > 127 || fabs(delta.y) > 127) {
			int steps = MAX(ceil(delta.x / 127.0), ceil(delta.y / 127.0));
			[_string appendString:@",9"];
			_byteCount++;
			for (int i = 1; i < steps; i++) {
				[_string appendFormat:@",(%d,%d)", (int)round(delta.x / i), (int)round(delta.y / i)];
				_byteCount++;
				_byteCount++;
			}
			[_string appendString:@",(0,0)"];
			_byteCount++;
			_byteCount++;
		}
		else {
			[_string appendFormat:@",8,(%d,%d)", (int)round(delta.x), (int)round(delta.y)];
			_byteCount++;
			_byteCount++;
			_byteCount++;
		}
	}
	_lastPoint = pt;
}

- (void)startGlyph:(GSLayer*)layer {
	UKLog(@"__name:%@", layer.glyph.name);
	_string = [[NSMutableString alloc] init];
	_byteCount = 0;
}

- (void)endGlyph:(GSLayer*)layer {
	[self moveTo:NSMakePoint(layer.width, 0)];
	if ([_string length] > 1 && [_string characterAtIndex:0] == ',') {
		[_string replaceCharactersInRange:NSMakeRange(0, 1) withString:@""];
	}
	[_string appendString:@",0"];
	_byteCount++;
	
	NSRange comma;
	comma.length = 0;
	comma.location = 0;
	NSUInteger lastLine = 0;
	NSUInteger length = [_string length];
	while (length - lastLine > 120) {
		comma = [_string rangeOfString:@"," options:NSBackwardsSearch range:NSMakeRange(lastLine, 120)];
		if (comma.location < NSNotFound) {
			[_string replaceCharactersInRange:comma withString:@",\n"];
			length++;
			lastLine = comma.location + 2;
		}
		else {
			break;
		}
	}
}

- (void)moveTo:(NSPoint)pt {
	[self drawLine:pt mode:2];
	_lastMovePoint = _lastPoint;
}

- (void)lineTo:(NSPoint)pt {
	[self drawLine:pt mode:1];
}

- (void)curveTo:(NSPoint)pt off1:(NSPoint)off1 off2:(NSPoint)off2 {
	CGFloat length = GSLengthOfSegment(_lastPoint, off1, off2, pt);
	CGFloat stepLength = 10;
	if (length > 2) {
		CGFloat steps = ceil(length / stepLength);
		[self setMode:1];
		[_string appendString:@",13"];
		_byteCount++;
		NSPoint l = _lastPoint;
		NSPoint n1 = GSAddPoints(GSNormalVector1(GSSubtractPoints(off1, _lastPoint)), _lastPoint);
		for (CGFloat i = 1; i <= steps; i++) {
			UKLog(@"__c: i:%d", (int)i);
			NSPoint q1, q2, q3, q4, r2, r3, r4;
			GSDividSegment(_lastPoint, off1, off2, pt, &q1, &q2, &q3, &q4, &r2, &r3, &r4, i / steps);
			NSPoint n2 = GSAddPoints(GSNormalVector2(GSSubtractPoints(q3, q4)), q4);
			NSPoint p = GSRoundPoint(q4);
			p = q4;
			//UKLog(@"__c: l:%@ m:%@ p:%@", NSStringFromPoint(l), NSStringFromPoint(center), NSStringFromPoint(p));
			
			
			NSPoint center = GSIntersectLineLineUnlimited(l, n1, q4, n2);
			CGFloat a = GSDistance(center, l);
			CGFloat d = GSDistance(l, p);
			UKLog(@"__h:  a:%.3f d:%.3f s:%.3f, sq:%.3f", a*a, (d*d/4), a*a-(d*d/4), sqrt(a*a-(d*d/4)));
			CGFloat h = a - sqrt(a*a-(d*d/4));
			UKLog(@"__h:  a:%.3f", h);
			BOOL CCW = GSPointIsLeftOfLine(l, p, center);
			int b = round(254 * h / d);
			if (!CCW) {
				b = -b;
			}
			NSPoint delta = GSSubtractPoints(GSRoundPoint(p), GSRoundPoint(l));
			
			UKLog(@"__c: l:%@ m:%@ p:%@", NSStringFromPoint(l), NSStringFromPoint(center), NSStringFromPoint(p));
			UKLog(@"__c: a:%.3f  h:%.3f  d:%.3f  b:%d", a, h, d, b);
			
			[_string appendFormat:@",(%d,%d,%d)", (int)delta.x, (int)delta.y, b];
			_byteCount++;
			_byteCount++;
			_byteCount++;
			l = p;
			n1 = n2;
		}
		[_string appendString:@",(0,0)"];
		_byteCount++;
		_byteCount++;
		_lastPoint = pt;
	}
	else {
		[self lineTo:pt];
	}
}

- (void)closePath {
	if (GSDistance(_lastPoint, _lastMovePoint) > 1) {
		[self lineTo:_lastMovePoint];
	}
}

- (void)addComponent:(GSComponent *)component transformation:(NSAffineTransform *)transformation {
	
}

- (void)endPath {}
- (void)qCurveTo:(NSArray *)Points {}

@end

@implementation AutoCADShapeExporter

@synthesize exportSettingsView = _exportSettingsView;
@synthesize font = _font;
@synthesize progressWindow = _progressWindow;

- (id)init {
	self = [super init];
	if (![NSBundle loadNibNamed:@"AutoCADShapeExporterDialog" owner:self]) {
		NSLog(@"error loading nib");
	}
	NSBundle * thisBundle = [NSBundle bundleForClass:[self class]];
	_toolbarIcon = [[NSImage alloc] initWithContentsOfFile:[thisBundle pathForImageResource: @"ExportIcon"]];
	[_toolbarIcon setName: @"AutoCAD"];
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{@"AutoCADExportPath": [@"~/Documents" stringByExpandingTildeInPath]}];
	return self;
}

- (NSUInteger)interfaceVersion {
	// Distinguishes the API verison the plugin was built for. Return 1.
	return 1;
}

- (NSString*)title {
	// Return the name of the tool as it will appear in export dialog.
	return @"AutoCADShapeExporter";
}

- (NSString*)toolbarTitle {
	// Return the name of the tool as it will appear in export dialog.
	return @"AutoCAD";
}

- (NSUInteger)groupID {
	// Position in the export panel. Higher numbers move it to the right.
	return 10;
}

- (IBAction)openDoc:(id)sender {
	
	NSOpenPanel *oPanel = [NSOpenPanel openPanel];
	
	[oPanel setAllowsMultipleSelection:NO];
	[oPanel setCanChooseFiles:NO];
	[oPanel setCanChooseDirectories:YES];
	[oPanel setCanCreateDirectories:YES];
	NSString *FontFolder = [[NSUserDefaults standardUserDefaults] objectForKey:@"AutoCADExportPath"];
	
	BOOL isDir;
	if (!FontFolder || ![[NSFileManager defaultManager] fileExistsAtPath:FontFolder isDirectory:&isDir]) {
		FontFolder = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
	}
	
	[oPanel setDirectoryURL:[NSURL URLWithString:FontFolder]];
	
	[oPanel beginSheetModalForWindow:[[self exportSettingsView] window] completionHandler:^(NSInteger result) {
		if (result == NSOKButton) {
			NSArray *filesToOpen = [oPanel URLs];
			NSString *Path = nil;
			if ([filesToOpen count] > 0) {
				NSURL *aURL = filesToOpen[0];
				Path = [aURL path];
			}
			if ([Path length] < 2) {
				[oPanel orderOut:nil];
				NSDictionary *errorDetail = @{NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Please select a valid folder.", nil, [NSBundle bundleForClass:[self class]], @"Export Panel")};
				NSError *error = [NSError errorWithDomain:@"GSGlyphsDomain" code:1 userInfo:errorDetail];
				[[NSApplication sharedApplication] presentError:error modalForWindow:[[self exportSettingsView] window] delegate:nil didPresentSelector:nil contextInfo:nil];
				return;
			}
			[[NSUserDefaults standardUserDefaults] setObject:Path forKey:@"AutoCADExportPath"];
		}
	}];
}

- (GSFont *)fontFromURL:(NSURL *)URL ofType:(NSString *)Type error:(out NSError *__autoreleasing*)error {
	// Load the font at URL and return a GSFont object.
	return nil;
}

- (BOOL)writeFont:(GSFont*)Font error:(out NSError*__autoreleasing*)error {
	NSURL *DestinationURL = nil;
	_font = Font;
	if ([[NSUserDefaults standardUserDefaults] objectForKey:@"AutoCADExportPath"] && [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoCADUseExportPath"]) {
		BOOL isDir;
		if ([[NSFileManager defaultManager] fileExistsAtPath:[[NSUserDefaults standardUserDefaults] objectForKey:@"AutoCADExportPath"] isDirectory:&isDir] && isDir) {
			DestinationURL = [NSURL fileURLWithPath:[[NSUserDefaults standardUserDefaults] objectForKey:@"AutoCADExportPath"]];
		}
	}
	if (!DestinationURL) {
		NSOpenPanel *openPanel = [NSOpenPanel openPanel];
		if ([[NSUserDefaults standardUserDefaults] objectForKey:@"AutoCADExportPathManual"]) {
			[openPanel setDirectoryURL:[NSURL fileURLWithPath:[[NSUserDefaults standardUserDefaults] objectForKey:@"AutoCADExportPathManual"]]];
		}
		else if ([[NSUserDefaults standardUserDefaults] objectForKey:@"AutoCADExportPath"]) {
			[openPanel setDirectoryURL:[NSURL fileURLWithPath:[[NSUserDefaults standardUserDefaults] objectForKey:@"AutoCADExportPath"]]];
		}
		[openPanel setCanChooseDirectories:YES];
		[openPanel setAllowsMultipleSelection:NO];
		[openPanel setCanCreateDirectories:YES];
		[openPanel setTitle:NSLocalizedStringFromTableInBundle(@"Choose folder.", nil, [NSBundle bundleForClass:[self class]], @"Export Panel")];
		[openPanel setPrompt:NSLocalizedStringFromTableInBundle(@"Export Font", nil, [NSBundle bundleForClass:[self class]], @"Export Panel")];
		[openPanel setCanChooseFiles:NO];
		NSInteger sheetResult = NSNotFound;
		sheetResult = [openPanel runModalForDirectoryURL:nil file:nil types:nil relativeToWindow:[(NSDocument *)Font.parent windowForSheet]];
		if (sheetResult == NSFileHandlingPanelOKButton) {
			DestinationURL = [openPanel URLs][0];
			[[NSUserDefaults standardUserDefaults] setObject:[DestinationURL path] forKey:@"AutoCADExportPathManual"];
		}
	}
	if (DestinationURL) {
		BOOL Result = [self exportToURL:DestinationURL error:error];
		return Result;
	}
	return YES;

}

- (BOOL)writeLayer:(GSLayer *)layer toString:(NSMutableString *)string error:(NSError *__autoreleasing*)error {
	AutoCadPen *pen = [[AutoCadPen alloc] init];
	[layer drawInPen:pen];
	NSUInteger byteCount = pen.byteCount;
	if (byteCount > 0) {
		[string appendFormat:@"*0%@,%ld,%@\n%@\n", layer.glyph.unicode, byteCount, layer.glyph.name, pen.string];
	}
	return YES;
}

- (BOOL)writeFont:(GSFont*)Font toURL:(NSURL*)DestinationURL error:(out NSError*__autoreleasing*)error {
	return NO;
}

- (BOOL)exportToURL:(NSURL *)DestinationURL error:(out NSError*__autoreleasing*)error {
	if (DestinationURL) {
		@try {
			if ([_font.instances count] == 0) {
				[_font addInstance:[[GSInstance alloc] init]];
			}
			for (GSInstance *instance in _font.instances) {
				
				GSFont *InterFont = [_font generateInstance:instance error:error];
				GSFontMaster *master = [InterFont fontMasterAtIndex:0];
				NSMutableString *File = [NSMutableString string];
				
				NSString *FontName = [instance fontName];
				[File appendFormat:@"*UNIFONT,6,%@\n", FontName];
				
				NSInteger Ascender = (NSInteger)abs((int)round(master.ascender));
				NSInteger Descender = (NSInteger)abs((int)round(master.descender));

				[File appendFormat:@"%ld,%ld,0,0,0,0", Ascender, Descender];
				[File appendFormat:@"\n*10,5,lf\n2,8,(0,-%ld),0\n", InterFont.unitsPerEm];
				
				for (GSGlyph *glyph in InterFont.glyphs) {
					if ([glyph.unicode length] < 4) {
						continue;
					}
					GSLayer *layer = [glyph layerForKey:master.id];
					if (![self writeLayer:layer toString:File error:error]) {
						return NO;
					}
				}
				NSURL *InstanceURL = [DestinationURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.shp", [instance fontName]]];
				[File replaceOccurrencesOfString:@"\n" withString:@"\r\n" options:0 range:NSMakeRange(0, [File length])];
				[File writeToURL:InstanceURL atomically:YES encoding:NSISOLatin1StringEncoding error:error];
			}
		}
		@catch (NSException *exception) {
			if (error) {
				NSDictionary *errorDetail = @{NSUnderlyingErrorKey: exception};
				*error = [[NSError alloc] initWithDomain:@"GSGlyphsDomain" code:11 userInfo:errorDetail];
			}
			return NO;
		}
	}
	return YES;
}

- (NSString *)toolbarIconName {
	return @"AutoCAD";
}

@end
