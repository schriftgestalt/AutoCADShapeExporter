//
//  AutoCADShapeExporter.m
//  AutoCADShapeExporter
//
//  Created by Georg Seifert on 20.01.16.
//  Copyright © 2016 Georg Seifert. All rights reserved.
//

#import "AutoCADShapeExporter.h"
#import <GlyphsCore/GSFont.h>
#import <GlyphsCore/GSFontMaster.h>
#import <GlyphsCore/GSGlyph.h>
#import <GlyphsCore/GSInstance.h>
#import <GlyphsCore/GSLayer.h>
#import <GlyphsCore/GSNode.h>
#import <GlyphsCore/GSPath.h>
#import <GlyphsCore/GSComponent.h>
#import <GlyphsCore/GlyphsFilterProtocol.h>
#import <GlyphsCore/GSPenProtocol.h>
#import <GlyphsCore/GSGeometrieHelper.h>
#import <GlyphsCore/GSModalOpenPanel.h>

void drawLine(NSPoint line, NSMutableString *string, NSUInteger *count);
void drawLine(NSPoint line, NSMutableString *string, NSUInteger *count) {
	if (fabs(line.x) > 127 || fabs(line.y) > 127) {
		int steps = MAX(ceil(fabs(line.x / 127.0)), ceil(fabs(line.y / 127.0)));
		[string appendString:@",9"];
		(*count)++;
		for (int i = 0; i < steps; i++) {
			int stepX = round(line.x / (steps - i));
			int stepY = round(line.y / (steps - i));
			[string appendFormat:@",(%d,%d)", stepX, stepY];
			*count += 2;
			line.x -= stepX;
			line.y -= stepY;
		}
		[string appendString:@",(0,0)"];
		*count += 2;
	}
	else {
		[string appendFormat:@",8,(%d,%d)", (int)round(line.x), (int)round(line.y)];
		*count += 3;
	}
}

@interface AutoCadPen : NSObject <GSPenProtocol> {
	NSPoint _lastMovePoint;
	int _currentMode;
}

@property (nonatomic) NSUInteger byteCount;
@property (nonatomic) NSPoint lastPoint;
@property (nonatomic, strong) NSMutableString *string;
@property (nonatomic, strong) NSAffineTransform *transform;
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
		drawLine(delta, _string, &_byteCount);
	}
	_lastPoint = pt;
}

- (void)startGlyph:(GSLayer *)layer {
	GSLog(@"__name:%@", layer.glyph.name);
	_string = [[NSMutableString alloc] init];
	_byteCount = 0;
}

- (void)endGlyph:(GSLayer *)layer {
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
	if (_transform)
		pt = [_transform transformPoint:pt];
	[self drawLine:pt mode:2];
	_lastMovePoint = _lastPoint;
}

- (void)lineTo:(NSPoint)pt {
	if (_transform)
		pt = [_transform transformPoint:pt];
	[self drawLine:pt mode:1];
}

- (void)curveTo:(NSPoint)pt off1:(NSPoint)off1 off2:(NSPoint)off2 {
	if (_transform) {
		pt = [_transform transformPoint:pt];
		off1 = [_transform transformPoint:off1];
		off2 = [_transform transformPoint:off2];
	}
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
			GSLog(@"__c: i:%d", (int)i);
			NSPoint q1, q2, q3, q4, r2, r3, r4;
			GSDividBezier3Points(_lastPoint, off1, off2, pt, &q1, &q2, &q3, &q4, &r2, &r3, &r4, i / steps);
			NSPoint n2 = GSAddPoints(GSNormalVector2(GSSubtractPoints(q3, q4)), q4);
			NSPoint p = GSRoundPoint(q4);
			p = q4;
			// GSLog(@"__c: l:%@ m:%@ p:%@", NSStringFromPoint(l), NSStringFromPoint(center), NSStringFromPoint(p));

			NSPoint center = GSIntersectLineLineUnlimited(l, n1, q4, n2);
			CGFloat a = GSDistance(center, l);
			CGFloat d = GSDistance(l, p);
			GSLog(@"__h:  a:%.3f d:%.3f s:%.3f, sq:%.3f", a * a, (d * d / 4), a * a - (d * d / 4), sqrt(a * a - (d * d / 4)));
			CGFloat h = a - sqrt(a * a - (d * d / 4));
			GSLog(@"__h:  a:%.3f", h);
			BOOL CCW = GSPointIsLeftOfLine(l, p, center);
			int b = round(254 * h / d);
			if (!CCW) {
				b = -b;
			}
			NSPoint delta = GSSubtractPoints(GSRoundPoint(p), GSRoundPoint(l));

			GSLog(@"__c: l:%@ m:%@ p:%@", NSStringFromPoint(l), NSStringFromPoint(center), NSStringFromPoint(p));
			GSLog(@"__c: a:%.3f  h:%.3f  d:%.3f  b:%d", a, h, d, b);

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
	NSAffineTransform *oldTransform = [_transform copy];
	if (_transform) {
		[_transform prependTransform:transformation];
	}
	else {
		_transform = transformation;
	}
	if ([component isKindOfClass:[GSComponent class]]) {
		GSLayer *compLayer = [component componentLayer];
		for (GSShape *shape in compLayer.shapes) {
			[shape drawInPen:self];
		}
	}
	_transform = oldTransform;
}

- (void)endPath {
}

- (void)qCurveTo:(NSArray *)Points {
}

@end

@implementation AutoCADShapeExporter

@synthesize exportSettingsView = _exportSettingsView;
@synthesize font = _font;
@synthesize progressWindow = _progressWindow;

- (id)init {
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	self = [super initWithNibName:@"AutoCADShapeExporterDialog" bundle:bundle];

	_toolbarIcon = [[NSImage alloc] initWithContentsOfFile:[bundle pathForImageResource:@"ExportIcon"]];
	[_toolbarIcon setName:@"AutoCAD"];
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{@"AutoCADExportPath": [@"~/Documents" stringByExpandingTildeInPath]}];
	return self;
}

- (NSUInteger)interfaceVersion {
	// Distinguishes the API verison the plugin was built for. Return 1.
	return 1;
}

- (NSString *)title {
	// Return the name of the tool as it will appear in export dialog.
	return @"AutoCADShapeExporter";
}

- (NSString *)toolbarTitle {
	// Return the name of the tool as it will appear in export dialog.
	return @"AutoCAD";
}

- (NSUInteger)groupID {
	// Position in the export panel. Higher numbers move it to the right.
	return 10;
}

- (NSView *)exportSettingsView {
	return self.view;
}

- (IBAction)openDoc:(id)sender {

	NSOpenPanel *oPanel = [NSOpenPanel openPanel];
	[oPanel setAllowsMultipleSelection:NO];
	[oPanel setCanChooseFiles:NO];
	[oPanel setCanChooseDirectories:YES];
	[oPanel setCanCreateDirectories:YES];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *fontFolder = [defaults objectForKey:@"AutoCADExportPath"];

	BOOL isDir;
	if (!fontFolder || ![[NSFileManager defaultManager] fileExistsAtPath:fontFolder isDirectory:&isDir]) {
		fontFolder = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
	}

	[oPanel setDirectoryURL:[NSURL URLWithString:fontFolder]];

	[oPanel beginSheetModalForWindow:[[self exportSettingsView] window]
				   completionHandler:^(NSModalResponse result) {
		if (result == NSModalResponseOK) {
			NSArray *filesToOpen = [oPanel URLs];
			NSString *path = nil;
			if ([filesToOpen count] > 0) {
				NSURL *aURL = filesToOpen[0];
				path = [aURL path];
			}
			if ([path length] < 2) {
				[oPanel orderOut:nil];
				NSDictionary *errorDetail = @{NSLocalizedDescriptionKey: NSLocalizedStringFromTableInBundle(@"Please select a valid folder.", nil, [NSBundle bundleForClass:[self class]], @"Export Panel")};
				NSError *error = [NSError errorWithDomain:@"GSGlyphsDomain" code:1 userInfo:errorDetail];
				[[NSApplication sharedApplication] presentError:error modalForWindow:[[self exportSettingsView] window] delegate:nil didPresentSelector:nil contextInfo:nil];
				return;
			}
			[defaults setObject:path forKey:@"AutoCADExportPath"];
		}
	}];
}

- (GSFont *)fontFromURL:(NSURL *)URL ofType:(NSString *)Type error:(out NSError *__autoreleasing *)error {
	// Load the font at URL and return a GSFont object.
	return nil;
}

- (void)exportFont:(GSFont *)font {
	__block NSURL *destinationURL = nil;
	_font = font;
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:@"AutoCADExportPath"] && [defaults boolForKey:@"AutoCADUseExportPath"]) {
		BOOL isDir;
		if ([[NSFileManager defaultManager] fileExistsAtPath:[defaults objectForKey:@"AutoCADExportPath"] isDirectory:&isDir] && isDir) {
			destinationURL = [NSURL fileURLWithPath:[defaults objectForKey:@"AutoCADExportPath"]];
		}
	}
	if (!destinationURL) {
		NSOpenPanel *openPanel = [NSOpenPanel openPanel];
		if ([defaults objectForKey:@"AutoCADExportPathManual"]) {
			[openPanel setDirectoryURL:[NSURL fileURLWithPath:[defaults objectForKey:@"AutoCADExportPathManual"]]];
		}
		else if ([defaults objectForKey:@"AutoCADExportPath"]) {
			[openPanel setDirectoryURL:[NSURL fileURLWithPath:[defaults objectForKey:@"AutoCADExportPath"]]];
		}
		[openPanel setCanChooseDirectories:YES];
		[openPanel setAllowsMultipleSelection:NO];
		[openPanel setCanCreateDirectories:YES];
		[openPanel setTitle:NSLocalizedStringFromTableInBundle(@"Choose Folder", nil, [NSBundle bundleForClass:[self class]], @"Export Panel")];
		[openPanel setPrompt:NSLocalizedStringFromTableInBundle(@"Export Font", nil, [NSBundle bundleForClass:[self class]], @"Export Panel")];
		[openPanel setCanChooseFiles:NO];
		[openPanel beginSheetModalForWindow:[(NSDocument *)font.parent windowForSheet]
						  completionHandler:^(NSModalResponse result) {
			if (result == NSFileHandlingPanelOKButton) {
				destinationURL = [openPanel URLs].firstObject;
				[defaults setObject:[destinationURL path] forKey:@"AutoCADExportPathManual"];
				NSError *error = nil;
				if (![self exportToURL:destinationURL error:&error]) {
					[(NSDocument *)font.parent presentError:error];
				}
			}
		}];
	}
	else {
		NSError *error = nil;
		if (![self exportToURL:destinationURL error:&error]) {
			[(NSDocument *)font.parent presentError:error];
		}
	}
}

- (BOOL)writeLayer:(GSLayer *)layer toString:(NSMutableString *)string error:(NSError *__autoreleasing *)error {
	AutoCadPen *pen = [[AutoCadPen alloc] init];
	[layer drawInPen:pen];
	NSUInteger byteCount = pen.byteCount;
	if (byteCount > 0) {
		[string appendFormat:@"*0%@,%ld,%@\n%@\n", layer.glyph.unicode, byteCount, layer.glyph.name, pen.string];
	}
	return YES;
}

- (BOOL)writeFont:(GSFont *)font toURL:(NSURL *)URL error:(out NSError **)error {
	return NO;
}

- (BOOL)exportToURL:(NSURL *)destinationURL error:(out NSError *__autoreleasing *)error {
	if (destinationURL) {
		@try {
			if ([_font.instances count] == 0) {
				[_font addInstance:[[GSInstance alloc] init]];
			}
			for (GSInstance *instance in _font.instances) {

				GSFont *interFont = [_font generateInstance:instance error:error];
				GSFontMaster *master = [interFont fontMasterAtIndex:0];
				NSMutableString *file = [NSMutableString string];

				NSString *fontName = [instance fontName:nil];
				[file appendFormat:@"*UNIFONT,6,%@\n", fontName];

				NSInteger ascender = (NSInteger)abs((int)round(master.defaultAscender));
				NSInteger descender = (NSInteger)abs((int)round(master.defaultDescender));

				[file appendFormat:@"%ld,%ld,0,0,0,0", ascender, descender];
				NSMutableString *lfString = [NSMutableString new];
				NSUInteger lfByteCount = 2;
				drawLine(NSMakePoint(0, -(int)interFont.unitsPerEm), lfString, &lfByteCount);
				if ([lfString length] > 1 && [lfString characterAtIndex:0] == ',') {
					[lfString replaceCharactersInRange:NSMakeRange(0, 1) withString:@""];
				}
				[file appendFormat:@"\n*10,%ld,lf\n2,%@,0\n", lfByteCount, lfString];

				for (GSGlyph *glyph in interFont.glyphs) {
					if (!glyph.export || glyph.unicodes.count == 0) {
						continue;
					}
					GSLayer *layer = [glyph layerForId:master.id];
					if (![self writeLayer:layer toString:file error:error]) {
						return NO;
					}
				}
				NSString *fileName = [instance fileName:@"shp" error:nil];
				NSURL *instanceURL = [destinationURL URLByAppendingPathComponent:fileName];
				[file replaceOccurrencesOfString:@"\n" withString:@"\r\n" options:0 range:NSMakeRange(0, [file length])];
				[file writeToURL:instanceURL atomically:YES encoding:NSISOLatin1StringEncoding error:error];
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
