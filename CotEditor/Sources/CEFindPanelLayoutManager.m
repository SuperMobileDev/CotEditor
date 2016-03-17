/*
 
 CEFindPanelLayoutManager.m
 
 CotEditor
 http://coteditor.com
 
 Created by 1024jp on 2015-03-04.

 ------------------------------------------------------------------------------
 
 © 2015 1024jp
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 
 */

#import "CEFindPanelLayoutManager.h"
#import "CEUtils.h"
#import "Constants.h"


@interface CEFindPanelLayoutManager ()

@property (nonatomic) CGFloat fontSize;

@end




#pragma mark -

@implementation CEFindPanelLayoutManager


#pragma mark Superclass Methods

// ------------------------------------------------------
/// initialize instance
- (nonnull instancetype)init
// ------------------------------------------------------
{
    self = [super init];
    if (self) {
        _fontSize = [NSFont systemFontSize];
        [self setUsesScreenFonts:YES];
    }
    return self;
}

// ------------------------------------------------------
/// show invisible characters
- (void)drawGlyphsForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin
// ------------------------------------------------------
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if ([defaults boolForKey:CEDefaultShowInvisiblesKey]) {
        NSTextView *textView = [self firstTextView];
        NSString *completeString = [NSString stringWithString:[[self textStorage] string]];
        NSUInteger lengthToRedraw = NSMaxRange(glyphsToShow);
        NSSize inset = [textView textContainerInset];
        
        NSColor *color;
        if (NSAppKitVersionNumber >= NSAppKitVersionNumber10_10) {
            color = [NSColor tertiaryLabelColor];
        } else {
            color = [NSColor colorWithCalibratedWhite:0.0 alpha:0.25];
        }
        
        NSFont *font = [[self firstTextView] font];
        font = [font screenFont] ? : font;
        NSDictionary<NSString *, id> *attributes = @{NSFontAttributeName: font,
                                                     NSForegroundColorAttributeName: color};
        NSFont *fullwidthFont = [[NSFont fontWithName:@"HiraKakuProN-W3" size:[font pointSize]] screenFont] ? : font;
        NSDictionary<NSString *, id> *fullwidthAttributes = @{NSFontAttributeName: fullwidthFont,
                                                              NSForegroundColorAttributeName: color};
        NSFont *replaceFont;
        
        BOOL showsSpace = [defaults boolForKey:CEDefaultShowInvisibleSpaceKey];
        BOOL showsTab = [defaults boolForKey:CEDefaultShowInvisibleTabKey];
        BOOL showsNewLine = [defaults boolForKey:CEDefaultShowInvisibleNewLineKey];
        BOOL showsFullwidthSpace = [defaults boolForKey:CEDefaultShowInvisibleFullwidthSpaceKey];
        BOOL showsVerticalTab = [defaults boolForKey:CEDefaultShowOtherInvisibleCharsKey];
        BOOL showsOtherInvisibles = [defaults boolForKey:CEDefaultShowOtherInvisibleCharsKey];
        
        unichar spaceChar = [CEUtils invisibleSpaceChar:[defaults integerForKey:CEDefaultInvisibleSpaceKey]];
        NSAttributedString *space = [[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&spaceChar length:1]
                                                                    attributes:attributes];
        
        unichar tabChar = [CEUtils invisibleTabChar:[defaults integerForKey:CEDefaultInvisibleTabKey]];
        NSAttributedString *tab = [[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&tabChar length:1]
                                                                  attributes:attributes];
        
        unichar newLineChar = [CEUtils invisibleNewLineChar:[defaults integerForKey:CEDefaultInvisibleNewLineKey]];
        NSAttributedString *newLine = [[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&newLineChar length:1]
                                                                      attributes:attributes];
        
        unichar fullwidthSpaceChar = [CEUtils invisibleFullwidthSpaceChar:[defaults integerForKey:CEDefaultInvisibleFullwidthSpaceKey]];
        NSAttributedString *fullwidthSpace = [[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&fullwidthSpaceChar length:1]
                                                                             attributes:fullwidthAttributes];
        
        NSAttributedString *verticalTab = [[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&kVerticalTabChar length:1]
                                                                          attributes:attributes];
        
        for (NSUInteger glyphIndex = glyphsToShow.location; glyphIndex < lengthToRedraw; glyphIndex++) {
            NSUInteger charIndex = [self characterIndexForGlyphAtIndex:glyphIndex];
            unichar character = [completeString characterAtIndex:charIndex];
            
            NSAttributedString *glyphString = nil;
            switch (character) {
                case ' ':
                case 0x00A0:
                    if (!showsSpace) { continue; }
                    glyphString = space;
                    break;
                    
                case '\t':
                    if (!showsTab) { continue; }
                    glyphString = tab;
                    break;
                    
                case '\n':
                    if (!showsNewLine) { continue; }
                    glyphString = newLine;
                    break;
                    
                case 0x3000:  // fullwidth-space (JP)
                    if (!showsFullwidthSpace) { continue; }
                    glyphString = fullwidthSpace;
                    break;
                    
                case '\v':
                    if (!showsVerticalTab) { continue; }
                    glyphString = verticalTab;
                    break;
                    
                default:
                    if (showsOtherInvisibles && ([self glyphAtIndex:glyphIndex isValidIndex:NULL] == NSControlGlyph)) {
                        NSGlyphInfo *currentGlyphInfo = [[self textStorage] attribute:NSGlyphInfoAttributeName atIndex:charIndex effectiveRange:NULL];
                        
                        if (currentGlyphInfo) { continue; }
                        
                        replaceFont = replaceFont ?: [NSFont fontWithName:@"Lucida Grande" size:[font pointSize]];
                        
                        NSRange charRange = [self characterRangeForGlyphRange:NSMakeRange(glyphIndex, 1) actualGlyphRange:NULL];
                        NSString *baseString = [completeString substringWithRange:charRange];
                        NSGlyphInfo *glyphInfo = [NSGlyphInfo glyphInfoWithGlyphName:@"replacement" forFont:replaceFont baseString:baseString];
                        
                        if (glyphInfo) {
                            // !!!: The following line can cause crash by binary document.
                            //      It's actually dangerous and to be detoured to modify textStorage while drawing.
                            //      (2015-09 by 1024jp)
                            [[self textStorage] addAttributes:@{NSGlyphInfoAttributeName: glyphInfo,
                                                                NSFontAttributeName: replaceFont,
                                                                NSForegroundColorAttributeName: color}
                                                        range:charRange];
                        }
                    }
                    continue;
            }
            
            NSPoint pointToDraw = [self pointToDrawGlyphAtIndex:glyphIndex adjust:inset];
            [glyphString drawAtPoint:pointToDraw];
        }
    }
    
    [super drawGlyphsForGlyphRange:glyphsToShow atPoint:origin];
}


// ------------------------------------------------------
/// fix vertical glyph location for mixed font
- (NSPoint)locationForGlyphAtIndex:(NSUInteger)glyphIndex
// ------------------------------------------------------
{
    NSPoint point = [super locationForGlyphAtIndex:glyphIndex];
    point.y = [[NSFont systemFontOfSize:[self fontSize]] ascender];
    
    return point;
}


// ------------------------------------------------------
/// fix line height for mixed font
- (void)setLineFragmentRect:(NSRect)fragmentRect forGlyphRange:(NSRange)glyphRange usedRect:(NSRect)usedRect
// ------------------------------------------------------
{
    static const CGFloat kLineSpacing = 4.0;
    CGFloat lineHeight = [self fontSize] + kLineSpacing;
    
    fragmentRect.size.height = lineHeight;
    usedRect.size.height = lineHeight;
    
    [super setLineFragmentRect:fragmentRect forGlyphRange:glyphRange usedRect:usedRect];
}



#pragma mark Private Methods

//------------------------------------------------------
/// calculate point to draw invisible character
- (NSPoint)pointToDrawGlyphAtIndex:(NSUInteger)glyphIndex adjust:(NSSize)size
//------------------------------------------------------
{
    NSPoint drawPoint = [self locationForGlyphAtIndex:glyphIndex];
    NSPoint lineOrigin = [self lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:NULL].origin;
    
    drawPoint.x += size.width;
    drawPoint.y = lineOrigin.y + size.height;
    
    return drawPoint;
}

@end
