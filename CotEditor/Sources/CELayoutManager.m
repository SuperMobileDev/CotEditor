/*
 
 CELayoutManager.m
 
 CotEditor
 http://coteditor.com
 
 Created by nakamuxu on 2005-01-10.

 ------------------------------------------------------------------------------
 
 © 2004-2007 nakamuxu
 © 2014-2015 1024jp
 
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

@import CoreText;
#import "CELayoutManager.h"
#import "CETextViewProtocol.h"
#import "CEATSTypesetter.h"
#import "CEUtils.h"
#import "Constants.h"


@interface CELayoutManager ()

@property (nonatomic) BOOL showsSpace;
@property (nonatomic) BOOL showsTab;
@property (nonatomic) BOOL showsNewLine;
@property (nonatomic) BOOL showsFullwidthSpace;
@property (nonatomic) BOOL showsOtherInvisibles;

@property (nonatomic) unichar spaceChar;
@property (nonatomic) unichar tabChar;
@property (nonatomic) unichar newLineChar;
@property (nonatomic) unichar fullwidthSpaceChar;

@property (nonatomic) CGFloat spaceWidth;

// readonly properties
@property (readwrite, nonatomic) CGFloat defaultLineHeightForTextFont;

@end




#pragma mark -

@implementation CELayoutManager

static CGGlyph ReplacementGlyph;
static BOOL usesTextFontForInvisibles;


#pragma mark Superclass Methods

// ------------------------------------------------------
/// initialize class
+ (void)initialize
// ------------------------------------------------------
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFont *lucidaGrande = [NSFont fontWithName:@"Lucida Grande" size:0];
        ReplacementGlyph = [lucidaGrande glyphWithName:@"replacement"];  // U+FFFD
        
        usesTextFontForInvisibles = [[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultUsesTextFontForInvisiblesKey];
    });
}


// ------------------------------------------------------
/// initialize
- (nonnull instancetype)init
// ------------------------------------------------------
{
    if (self = [super init]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        _spaceChar = [CEUtils invisibleSpaceChar:[defaults integerForKey:CEDefaultInvisibleSpaceKey]];
        _tabChar = [CEUtils invisibleTabChar:[defaults integerForKey:CEDefaultInvisibleTabKey]];
        _newLineChar = [CEUtils invisibleNewLineChar:[defaults integerForKey:CEDefaultInvisibleNewLineKey]];
        _fullwidthSpaceChar = [CEUtils invisibleFullwidthSpaceChar:[defaults integerForKey:CEDefaultInvisibleFullwidthSpaceKey]];

        // （setShowsInvisibles: は CEEditorView から実行される。プリント時は CEPrintView から実行される）
        _showsSpace = [defaults boolForKey:CEDefaultShowInvisibleSpaceKey];
        _showsTab = [defaults boolForKey:CEDefaultShowInvisibleTabKey];
        _showsNewLine = [defaults boolForKey:CEDefaultShowInvisibleNewLineKey];
        _showsFullwidthSpace = [defaults boolForKey:CEDefaultShowInvisibleFullwidthSpaceKey];
        _showsOtherInvisibles = [defaults boolForKey:CEDefaultShowOtherInvisibleCharsKey];
        
        [self setUsesScreenFonts:YES];
        [self setShowsControlCharacters:_showsOtherInvisibles];
        [self setTypesetter:[[CEATSTypesetter alloc] init]];
    }
    return self;
}


// ------------------------------------------------------
/// 行描画矩形をセット
- (void)setLineFragmentRect:(NSRect)fragmentRect forGlyphRange:(NSRange)glyphRange usedRect:(NSRect)usedRect
// ------------------------------------------------------
{
    if (![self isPrinting] && [self fixesLineHeight]) {
        // 複合フォントで行の高さがばらつくのを防止する
        // （CETextView で、NSParagraphStyle の lineSpacing を設定しても行間は制御できるが、
        // 「文書の1文字目に1バイト文字（または2バイト文字）を入力してある状態で先頭に2バイト文字（または1バイト文字）を
        // 挿入すると行間がズレる」問題が生じる））
        fragmentRect.size.height = [self lineHeight];
        usedRect.size.height = [self lineHeight];
    }

    [super setLineFragmentRect:fragmentRect forGlyphRange:glyphRange usedRect:usedRect];
}


// ------------------------------------------------------
/// 最終行描画矩形をセット
- (void)setExtraLineFragmentRect:(NSRect)aRect usedRect:(NSRect)usedRect textContainer:(nonnull NSTextContainer *)aTextContainer
// ------------------------------------------------------
{
    // 複合フォントで行の高さがばらつくのを防止するために一般の行の高さを変更しているので、それにあわせる
    aRect.size.height = [self lineHeight];

    [super setExtraLineFragmentRect:aRect usedRect:usedRect textContainer:aTextContainer];
}


// ------------------------------------------------------
/// 不可視文字の表示
- (void)drawGlyphsForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin
// ------------------------------------------------------
{
    // スクリーン描画の時、アンチエイリアス制御
    if (![self isPrinting]) {
        [[NSGraphicsContext currentContext] setShouldAntialias:[self usesAntialias]];
    }
    
    // draw invisibles
    if ([self showsInvisibles]) {
        NSString *completeString = [[self textStorage] string];
        NSUInteger lengthToRedraw = NSMaxRange(glyphsToShow);
        
        // フォントサイズは随時変更されるため、表示時に取得する
        CTFontRef font = (__bridge CTFontRef)[self textFont];
        NSColor *color = [[(NSTextView<CETextViewProtocol> *)[self firstTextView] theme] invisiblesColor];
        
        // for other invisibles
        NSFont *replacementFont;  // delay creating font till it's really needed
        
        // set graphics context
        CGContextRef context = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
        CGContextSaveGState(context);
        CGContextSetFillColorWithColor(context, [color CGColor]);
        CGMutablePathRef paths = CGPathCreateMutable();
        
        // adjust drawing coordinate
        CGAffineTransform transform = CGAffineTransformIdentity;
        transform = CGAffineTransformScale(transform, 1.0, -1.0);  // flip
        transform = CGAffineTransformTranslate(transform, origin.x, - origin.y);
        CGContextConcatCTM(context, transform);
        
        // prepare glyphs
        CGPathRef spaceGlyphPath = glyphPathWithCharacter([self spaceChar], font, false);
        CGPathRef tabGlyphPath = glyphPathWithCharacter([self tabChar], font, false);
        CGPathRef newLineGlyphPath = glyphPathWithCharacter([self newLineChar], font, false);
        CGPathRef fullWidthSpaceGlyphPath = glyphPathWithCharacter([self fullwidthSpaceChar], font, true);
        CGPathRef verticalTabGlyphPath = glyphPathWithCharacter(kVerticalTabChar, font, true);
        
        // store value to avoid accessing properties each time  (2014-07 by 1024jp)
        BOOL showsSpace = [self showsSpace];
        BOOL showsTab = [self showsTab];
        BOOL showsNewLine = [self showsNewLine];
        BOOL showsFullwidthSpace = [self showsFullwidthSpace];
        BOOL showsVerticalTab = [self showsOtherInvisibles];  // Vertical tab belongs to other invisibles.
        BOOL showsOtherInvisibles = [self showsOtherInvisibles];
        
        // draw invisibles glyph by glyph
        for (NSUInteger glyphIndex = glyphsToShow.location; glyphIndex < lengthToRedraw; glyphIndex++) {
            NSUInteger charIndex = [self characterIndexForGlyphAtIndex:glyphIndex];
            unichar character = [completeString characterAtIndex:charIndex];
            
            CGPathRef glyphPath;
            switch (character) {
                case ' ':
                case 0x00A0:
                    if (!showsSpace) { continue; }
                    glyphPath = spaceGlyphPath;
                    break;
                    
                case '\t':
                    if (!showsTab) { continue; }
                    glyphPath = tabGlyphPath;
                    break;
                    
                case '\n':
                    if (!showsNewLine) { continue; }
                    glyphPath = newLineGlyphPath;
                    break;
                    
                case 0x3000:  // fullwidth-space (JP)
                    if (!showsFullwidthSpace) { continue; }
                    glyphPath = fullWidthSpaceGlyphPath;
                    break;
                    
                case '\v':
                    if (!showsVerticalTab) { continue; }
                    glyphPath = verticalTabGlyphPath;
                    break;
                    
                default:
                    if (showsOtherInvisibles && ([self glyphAtIndex:glyphIndex isValidIndex:NULL] == NSControlGlyph)) {
                        NSGlyphInfo *currentGlyphInfo = [[self textStorage] attribute:NSGlyphInfoAttributeName atIndex:charIndex effectiveRange:NULL];
                        
                        if (currentGlyphInfo) { continue; }
                        
                        NSRange charRange = NSMakeRange(charIndex, 1);
                        if (CFStringIsSurrogateHighCharacter(character)) {
                            if ((charIndex + 1 <= [completeString length]) &&
                                CFStringIsSurrogateLowCharacter([completeString characterAtIndex:charIndex + 1]))
                            {
                                charRange.length = 2;
                            }
                        }
                        
                        replacementFont = replacementFont ?: [NSFont fontWithName:@"Lucida Grande" size:[[self textFont] pointSize]];
                        
                        NSString *baseString = [completeString substringWithRange:charRange];
                        NSGlyphInfo *glyphInfo = [NSGlyphInfo glyphInfoWithGlyph:ReplacementGlyph forFont:replacementFont baseString:baseString];
                        
                        if (glyphInfo) {
                            // !!!: The following line can cause crash by binary document.
                            //      It's actually dangerous and to be detoured to modify textStorage while drawing.
                            //      (2015-09 by 1024jp)
                            [[self textStorage] addAttributes:@{NSGlyphInfoAttributeName: glyphInfo,
                                                                NSFontAttributeName: replacementFont,
                                                                NSForegroundColorAttributeName: color}
                                                        range:charRange];
                        }
                    }
                    continue;
            }
            
            // add invisible char path
            NSPoint point = [self pointToDrawGlyphAtIndex:glyphIndex];
            CGAffineTransform translate = CGAffineTransformMakeTranslation(point.x, -point.y);
            CGPathAddPath(paths, &translate, glyphPath);
        }
        
        // draw invisible glyphs (excl. other invisibles)
        CGContextAddPath(context, paths);
        CGContextFillPath(context);
        
        // release
        CGContextRestoreGState(context);
        CGPathRelease(paths);
        CGPathRelease(spaceGlyphPath);
        CGPathRelease(tabGlyphPath);
        CGPathRelease(newLineGlyphPath);
        CGPathRelease(fullWidthSpaceGlyphPath);
    }
    
    [super drawGlyphsForGlyphRange:glyphsToShow atPoint:origin];
}


// ------------------------------------------------------
/// textStorage did update
- (void)textStorage:(NSTextStorage *)str edited:(NSTextStorageEditedOptions)editedMask range:(NSRange)newCharRange changeInLength:(NSInteger)delta invalidatedRange:(NSRange)invalidatedCharRange
// ------------------------------------------------------
{
    // invalidate wrapping line indent in editRange if needed
    if (editedMask & NSTextStorageEditedCharacters &&
        [[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultEnablesHangingIndentKey])
    {
        // invoke after processEditing so that textStorage can be modified safety
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf invalidateIndentInRange:newCharRange];
        });
    }
    
    [super textStorage:str edited:editedMask range:newCharRange changeInLength:delta invalidatedRange:invalidatedCharRange];
}



#pragma mark Public Methods

// ------------------------------------------------------
/// [NSGraphicsContext currentContextDrawingToScreen] は真を返す時があるため、印刷用かを保持する専用フラグを用意
- (void)setPrinting:(BOOL)printing
// ------------------------------------------------------
{
    [self setUsesScreenFonts:!printing];
    
    _printing = printing;
}

// ------------------------------------------------------
/// 不可視文字を表示するかどうかを設定する
- (void)setShowsInvisibles:(BOOL)showsInvisibles
// ------------------------------------------------------
{
    if (!showsInvisibles) {
        NSRange range = NSMakeRange(0, [[[self textStorage] string] length]);
        [[self textStorage] removeAttribute:NSGlyphInfoAttributeName range:range];
    }
    if ([self showsOtherInvisibles]) {
        [self setShowsControlCharacters:showsInvisibles];
    }
    _showsInvisibles = showsInvisibles;
}


// ------------------------------------------------------
/// その他の不可視文字を表示するかどうかを設定する
- (void)setShowsOtherInvisibles:(BOOL)showsOtherInvisibles
// ------------------------------------------------------
{
    [self setShowsControlCharacters:showsOtherInvisibles];
    _showsOtherInvisibles = showsOtherInvisibles;
}


// ------------------------------------------------------
/// 表示フォントをセット
- (void)setTextFont:(nullable NSFont *)textFont
// ------------------------------------------------------
{
    // 複合フォントで行間が等間隔でなくなる問題を回避するため、自前でフォントを持っておく。
    // （[[self firstTextView] font] を使うと、「1バイトフォントを指定して日本語が入力されている」場合に
    // 日本語フォント名を返してくることがあるため、使わない）

    _textFont = textFont;
    [self setValuesForTextFont:textFont];
    
    // store width of space char for indent width calculation
    NSFont *screenFont = [textFont screenFont] ? : textFont;
    [self setSpaceWidth:[screenFont advancementForGlyph:(NSGlyph)' '].width];
}


// ------------------------------------------------------
/// 複合フォントで行の高さがばらつくのを防止するため、規定した行の高さを返す
- (CGFloat)lineHeight
// ------------------------------------------------------
{
    CGFloat lineSpacing = [(NSTextView<CETextViewProtocol> *)[self firstTextView] lineSpacing];

    // 小数点以下を返すと選択範囲が分離することがあるため、丸める
    return round([self defaultLineHeightForTextFont] + lineSpacing * [[self textFont] pointSize]);
}


// ------------------------------------------------------
/// invalidate indent of wrapped lines
- (void)invalidateIndentInRange:(NSRange)range
// ------------------------------------------------------
{
    // !!!: quick fix avoiding crash on typing Japanese text (2015-10)
    //  -> text length can be changed while passing run-loop
    if (NSMaxRange(range) > [[self textStorage] length]) {
        NSUInteger overflow = NSMaxRange(range) - [[self textStorage] length];
        if (range.length >= overflow) {
            range.length -= overflow;
        } else {
            // nothing to do about hanging indentation if changed range has already been completely removed
            return;
        }
    }
    
    CGFloat hangingIndent = [self spaceWidth] * [[NSUserDefaults standardUserDefaults] integerForKey:CEDefaultHangingIndentWidthKey];
    CGFloat linePadding = [[[self firstTextView] textContainer] lineFragmentPadding];
    NSTextStorage *textStorage = [self textStorage];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]+(?!$)" options:0 error:nil];
    
    NSMutableArray<NSDictionary<NSString *, id> *> *newIndents = [NSMutableArray array];
    
    // invalidate line by line
    NSRange lineRange = [[textStorage string] lineRangeForRange:range];
    __weak typeof(self) weakSelf = self;
    [[textStorage string] enumerateSubstringsInRange:lineRange
                                             options:NSStringEnumerationByLines | NSStringEnumerationSubstringNotRequired
                                          usingBlock:^(NSString *substring,
                                                       NSRange substringRange,
                                                       NSRange enclosingRange,
                                                       BOOL *stop)
     {
         typeof(weakSelf) self = weakSelf;
         if (!self) {
             *stop = YES;
             return;
         }
         
         CGFloat indent = hangingIndent;
         
         // add base indent
         NSRange baseIndentRange = [regex rangeOfFirstMatchInString:[textStorage string] options:0 range:substringRange];
         if (baseIndentRange.location != NSNotFound) {
             // getting the start line of the character jsut after the last indent character
             //   -> This is actually better in terms of performance than getting whole bounding rect using `boundingRectForGlyphRange:inTextContainer:`
             NSUInteger firstGlyphIndex = [self glyphIndexForCharacterAtIndex:NSMaxRange(baseIndentRange)];
             NSPoint firstGlyphLocation = [self locationForGlyphAtIndex:firstGlyphIndex];
             indent += firstGlyphLocation.x - linePadding;
         }
         
         // apply new indent only if needed
         NSParagraphStyle *paragraphStyle = [textStorage attribute:NSParagraphStyleAttributeName
                                                           atIndex:substringRange.location
                                                    effectiveRange:NULL];
         if (indent != [paragraphStyle headIndent]) {
             NSMutableParagraphStyle *mutableParagraphStyle = [paragraphStyle mutableCopy];
             [mutableParagraphStyle setHeadIndent:indent];
             
             // store the result
             //   -> Don't apply to the textStorage at this moment.
             [newIndents addObject:@{@"paragraphStyle": [mutableParagraphStyle copy],
                                     @"range": [NSValue valueWithRange:substringRange]}];
         }
     }];
    
    if ([newIndents count] == 0) { return; }
    
    // apply new paragraph styles at once
    //   -> This avoids letting layoutManager calculate glyph location each time.
    [textStorage beginEditing];
    for (NSDictionary<NSString *, id> *indent in newIndents) {
        NSRange range = [indent[@"range"] rangeValue];
        NSParagraphStyle *paragraphStyle = indent[@"paragraphStyle"];
        
        [textStorage addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:range];
    }
    [textStorage endEditing];
}



#pragma mark Private Methods

// ------------------------------------------------------
/// 表示フォントの各種値をキャッシュする
- (void)setValuesForTextFont:(nullable NSFont *)textFont
// ------------------------------------------------------
{
    if (textFont) {
        [self setDefaultLineHeightForTextFont:[self defaultLineHeightForFont:textFont] * kDefaultLineHeightMultiple];
        
    } else {
        [self setDefaultLineHeightForTextFont:0.0];
    }
}


//------------------------------------------------------
/// グリフを描画する位置を返す
- (NSPoint)pointToDrawGlyphAtIndex:(NSUInteger)glyphIndex
//------------------------------------------------------
{
    NSPoint drawPoint = [self locationForGlyphAtIndex:glyphIndex];
    NSPoint lineOrigin = [self lineFragmentRectForGlyphAtIndex:glyphIndex
                                                effectiveRange:NULL
                                       withoutAdditionalLayout:YES].origin;
    
    drawPoint.y += lineOrigin.y;
    
    return drawPoint;
}


//------------------------------------------------------
/// 文字とフォントからアウトラインパスを生成して返す
CGPathRef glyphPathWithCharacter(unichar character, CTFontRef font, bool prefersFullWidth)
//------------------------------------------------------
{
    CGFloat fontSize = CTFontGetSize(font);
    CGGlyph glyph;
    
    if (usesTextFontForInvisibles) {
        if (CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)) {
            return CTFontCreatePathForGlyph(font, glyph, NULL);
        }
    }
    
    // try fallback fonts in cases where user font doesn't support the input charactor
    // - All invisible characters of choices can be covered with the following two fonts.
    // - Monaco for vertical tab
    CGPathRef path = NULL;
    NSArray<NSString *> *fallbackFontNames = prefersFullWidth ? @[@"HiraKakuProN-W3", @"LucidaGrande", @"Monaco"] : @[@"LucidaGrande", @"HiraKakuProN-W3", @"Monaco"];
    
    for (NSString *fontName in fallbackFontNames) {
        CTFontRef fallbackFont = CTFontCreateWithName((CFStringRef)fontName, fontSize, 0);
        if (CTFontGetGlyphsForCharacters(fallbackFont, &character, &glyph, 1)) {
            path = CTFontCreatePathForGlyph(fallbackFont, glyph, NULL);
            break;
        }
        CFRelease(fallbackFont);
    }
    
    return path;
}

@end
