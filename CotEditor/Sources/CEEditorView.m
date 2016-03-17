/*
 
 CEEditorView.m
 
 CotEditor
 http://coteditor.com
 
 Created by nakamuxu on 2006-03-18.
 
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

#import "CEEditorView.h"
#import <OgreKit/OgreTextFinder.h>
#import "CEWindowController.h"
#import "CEEditorWrapper.h"
#import "CEEditorScrollView.h"
#import "CESyntaxParser.h"
#import "CEThemeManager.h"
#import "CETextFinder.h"
#import "NSString+CENewLine.h"
#import "Constants.h"


@interface CEEditorView ()

@property (nonatomic, nonnull) CEEditorScrollView *scrollView;
@property (nonatomic, nonnull) NSTextStorage *textStorage;

@property (nonatomic) BOOL highlightsCurrentLine;
@property (nonatomic) NSUInteger lastCursorLocation;


// readonly
@property (readwrite, nonnull, nonatomic) CETextView *textView;
@property (readwrite, nonnull, nonatomic) CENavigationBarController *navigationBar;

@end




#pragma mark -

@implementation CEEditorView

#pragma mark Superclass Methods

// ------------------------------------------------------
/// initialize instance
- (nonnull instancetype)initWithFrame:(NSRect)frameRect
// ------------------------------------------------------
{
    self = [super initWithFrame:frameRect];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        _highlightsCurrentLine = [defaults boolForKey:CEDefaultHighlightCurrentLineKey];

        // navigationBar 生成
        _navigationBar = [[CENavigationBarController alloc] init];
        [self addSubview:[_navigationBar view]];

        // create scroller with line number view
        _scrollView = [[CEEditorScrollView alloc] initWithFrame:NSZeroRect];
        [_scrollView setBorderType:NSNoBorder];
        [_scrollView setHasVerticalScroller:YES];
        [_scrollView setHasHorizontalScroller:YES];
        [_scrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [_scrollView setAutohidesScrollers:NO];
        [_scrollView setDrawsBackground:NO];
        [self addSubview:_scrollView];
        
        // setup autolayout
        NSDictionary<NSString *, __kindof NSView *> *views = @{@"navBar": [_navigationBar view],
                                                      @"scrollView": _scrollView};
        [[_navigationBar view] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[navBar]|"
                                                                     options:0 metrics:nil views:views]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[scrollView]|"
                                                                     options:0 metrics:nil views:views]];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[navBar][scrollView]|"
                                                                     options:0 metrics:nil views:views]];

        // TextStorage と LayoutManager を生成
        [self setTextStorage:[[NSTextStorage alloc] init]];
        CELayoutManager *layoutManager = [[CELayoutManager alloc] init];
        [_textStorage addLayoutManager:layoutManager];
        [layoutManager setBackgroundLayoutEnabled:YES];
        [layoutManager setUsesAntialias:[defaults boolForKey:CEDefaultShouldAntialiasKey]];
        [layoutManager setFixesLineHeight:[defaults boolForKey:CEDefaultFixLineHeightKey]];

        // NSTextContainer を生成
        NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
        [layoutManager addTextContainer:container];

        // TextView 生成
        _textView = [[CETextView alloc] initWithFrame:NSZeroRect textContainer:container];
        [_textView setDelegate:self];
        
        [_navigationBar setTextView:_textView];
        [_scrollView setDocumentView:_textView];
        
        // すべて置換アクションをキャッチ
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(textDidReplaceAll:)
                                                     name:CETextFinderDidReplaceAllNotification
                                                   object:_textView];
        
        // 置換の Undo/Redo 後に再カラーリングできるように Undo/Redo アクションをキャッチ
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recolorAfterUndoAndRedo:)
                                                     name:NSUndoManagerDidRedoChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recolorAfterUndoAndRedo:)
                                                     name:NSUndoManagerDidUndoChangeNotification
                                                   object:nil];
        
        // テーマの変更をキャッチ
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(themeDidUpdate:)
                                                     name:CEThemeDidUpdateNotification
                                                   object:nil];
        
        // リサイズに現在行ハイライトを追従
        if (_highlightsCurrentLine) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(highlightCurrentLine)
                                                         name:NSViewFrameDidChangeNotification
                                                       object:[_scrollView contentView]];
        }
    }
    return self;
}


// ------------------------------------------------------
/// clean up
- (void)dealloc
// ------------------------------------------------------
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_textStorage removeLayoutManager:[_textView layoutManager]];
    _textView = nil;
}



#pragma mark Public Methods

// ------------------------------------------------------
/// TextStorage を置換
- (void)replaceTextStorage:(nonnull NSTextStorage *)textStorage
// ------------------------------------------------------
{
    [[[self textView] layoutManager] replaceTextStorage:textStorage];
    [self setTextStorage:textStorage];
}


// ------------------------------------------------------
/// 行番号表示設定をセット
- (void)setShowsLineNum:(BOOL)showsLineNum
// ------------------------------------------------------
{
    [[self scrollView] setRulersVisible:showsLineNum];
}


// ------------------------------------------------------
/// ナビゲーションバーを表示／非表示
- (void)setShowsNavigationBar:(BOOL)showsNavigationBar animate:(BOOL)performAnimation;
// ------------------------------------------------------
{
    [[self navigationBar] setShown:showsNavigationBar animate:performAnimation];
}


// ------------------------------------------------------
/// ラップする／しないを切り替える
- (void)setWrapsLines:(BOOL)wrapsLines
// ------------------------------------------------------
{
    NSTextView *textView = [self textView];
    BOOL isVertical = ([textView layoutOrientation] == NSTextLayoutOrientationVertical);
    
    // 条件を揃えるためにいったん横書きに戻す (各項目の縦横の入れ替えは setLayoutOrientation: が良きに計らってくれる)
    [textView setLayoutOrientation:NSTextLayoutOrientationHorizontal];
    
    [[textView enclosingScrollView] setHasHorizontalScroller:!wrapsLines];
    [[textView textContainer] setWidthTracksTextView:wrapsLines];
    if (wrapsLines) {
        NSSize contentSize = [[textView enclosingScrollView] contentSize];
        [[textView textContainer] setContainerSize:NSMakeSize(contentSize.width, CGFLOAT_MAX)];
        [textView sizeToFit];
    } else {
        [[textView textContainer] setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    }
    [textView setAutoresizingMask:(wrapsLines ? NSViewWidthSizable : NSViewNotSizable)];
    [textView setHorizontallyResizable:!wrapsLines];
    
    // 縦書きモードの際は改めて縦書きにする
    if (isVertical) {
        [textView setLayoutOrientation:NSTextLayoutOrientationVertical];
    }
}


// ------------------------------------------------------
/// 不可視文字の表示／非表示を切り替える
- (void)setShowsInvisibles:(BOOL)showsInvisibles
// ------------------------------------------------------
{
    [(CELayoutManager *)[[self textView] layoutManager] setShowsInvisibles:showsInvisibles];
    
    // （不可視文字が選択状態で表示／非表示を切り替えられた時、不可視文字の背景選択色を描画するための時間差での選択処理）
    // （もっとスマートな解決方法はないものか...？ 2006-09-25）
    if (showsInvisibles) {
        __block NSTextView *textView = [self textView];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSRange selectedRange = [textView selectedRange];
            [textView setSelectedRange:NSMakeRange(0, 0)];
            [textView setSelectedRange:selectedRange];
        });
    }
}


// ------------------------------------------------------
/// アンチエイリアス適用を切り替える
- (void)setUsesAntialias:(BOOL)usesAntialias
// ------------------------------------------------------
{
    CELayoutManager *manager = (CELayoutManager *)[[self textView] layoutManager];

    [manager setUsesAntialias:usesAntialias];
    [[self textView] setNeedsDisplayInRect:[[self textView] visibleRect]];
}


// ------------------------------------------------------
/// キャレットを先頭に移動
- (void)setCaretToBeginning
// ------------------------------------------------------
{
    [[self textView] setSelectedRange:NSMakeRange(0, 0)];
}


// ------------------------------------------------------
/// シンタックススタイルを設定
- (void)applySyntax:(nonnull CESyntaxParser *)syntaxParser
// ------------------------------------------------------
{
    [[self textView] setInlineCommentDelimiter:[syntaxParser inlineCommentDelimiter]];
    [[self textView] setBlockCommentDelimiters:[syntaxParser blockCommentDelimiters]];
    [[self textView] setFirstCompletionCharacterSet:[syntaxParser firstCompletionCharacterSet]];
}


// ------------------------------------------------------
/// Undo/Redo の後に全てを再カラーリング
- (void)recolorAfterUndoAndRedo:(nonnull NSNotification *)aNotification
// ------------------------------------------------------
{
    NSUndoManager *undoManager = [aNotification object];
    
    if (undoManager != [[self textView] undoManager]) { return; }
    
    // OgreKit からの置換の Undo/Redo の後のみ再カラーリングを実行
    // 置換の Undo を判別するために OgreKit 側で登録された actionName を使用 (2014-04 by 1024jp)
    // [Note] OgreKit側の問題として、すべてのUndoに対して "Replace All" という名前を付けているようだ。なので現在「すべて」以外の置換も対象となっている (2014-12 by 1024jp)
    NSString *actionName = [undoManager isUndoing] ? [undoManager redoActionName] : [undoManager undoActionName];
    if ([actionName isEqualToString:OgreTextFinderLocalizedString(@"Replace All")]) {
        [self textDidReplaceAll:aNotification];
    }
}



#pragma mark Delegate

//=======================================================
// NSTextViewDelegate  < textView
//=======================================================

// ------------------------------------------------------
/// テキストが編集される
- (BOOL)textView:(nonnull NSTextView *)textView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(nullable NSString *)replacementString
// ------------------------------------------------------
{
    // standardize line endings to LF (Script, Key Typing)
    // (Line endings replacemement by other text modifications are processed in the following methods.)
    //
    // # Methods Standardizing Line Endings on Text Editing
    //   - File Open:
    //       - CEDocument > setStringToEditor
    //   - Key Typing, Script, Paste, Drop:
    //       - CEEditorView > textView:shouldChangeTextInRange:replacementString:
    //   - Replace on Find Panel:
    //       - (OgreKit) OgreTextViewPlainAdapter > replaceCharactersInRange:withOGString:
    
    if (!replacementString ||  // = attributesのみの変更
        ([replacementString length] == 0) ||  // = 文章の削除
        [[textView undoManager] isUndoing] ||  // = アンドゥ中
        [replacementString isEqualToString:@"\n"])
    {
        return YES;
    }
    
    // 挿入／置換する文字列に改行コードが含まれていたら、LF に置換する
    // （newStrが使用されるのはスクリプトからの入力時。キー入力は条件式を通過しない）
    CENewLineType replacementLineEndingType = [replacementString detectNewLineType];
    if ((replacementLineEndingType != CENewLineNone) && (replacementLineEndingType != CENewLineLF)) {
        NSString *newString = [replacementString stringByReplacingNewLineCharacersWith:CENewLineLF];
        
        [(CETextView *)textView replaceWithString:newString
                                            range:affectedCharRange
                                    selectedRange:NSMakeRange(affectedCharRange.location + [newString length], 0)
                                       actionName:nil];  // Action名は自動で付けられる？ので、指定しない
        
        return NO;
    }
    
    return YES;
}


// ------------------------------------------------------
/// 補完候補リストをセット
- (nonnull NSArray<NSString *> *)textView:(nonnull NSTextView *)textView completions:(nonnull NSArray<NSString *> *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(nullable NSInteger *)index
// ------------------------------------------------------
{
    NSMutableOrderedSet<NSString *> *candidateWords = [NSMutableOrderedSet orderedSet];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *partialWord = [[textView string] substringWithRange:charRange];

    // extract words in document and set to candidateWords
    if ([defaults boolForKey:CEDefaultCompletesDocumentWordsKey]) {
        if (charRange.length == 1 && ![[NSCharacterSet alphanumericCharacterSet] characterIsMember:[partialWord characterAtIndex:0]]) {
            // do nothing if the particle word is an symbol
            
        } else {
            NSString *documentString = [textView string];
            NSString *pattern = [NSString stringWithFormat:@"(?:^|\\b|(?<=\\W))%@\\w+?(?:$|\\b)",
                                 [NSRegularExpression escapedPatternForString:partialWord]];
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
            [regex enumerateMatchesInString:documentString options:0
                                      range:NSMakeRange(0, [documentString length])
                                 usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop)
             {
                 [candidateWords addObject:[documentString substringWithRange:[result range]]];
             }];
        }
    }
    
    // copy words defined in syntax style
    if ([defaults boolForKey:CEDefaultCompletesSyntaxWordsKey]) {
        NSArray<NSString *> *syntaxWords = [[self syntaxParser] completionWords];
        for (NSString *word in syntaxWords) {
            if ([word rangeOfString:partialWord options:NSCaseInsensitiveSearch|NSAnchoredSearch].location != NSNotFound) {
                [candidateWords addObject:word];
            }
        }
    }
    
    // copy the standard words from default completion words
    if ([defaults boolForKey:CEDefaultCompletesStandartWordsKey]) {
        [candidateWords addObjectsFromArray:words];
    }
    
    // provide nothing if there is only a candidate which is same as input word
    if ([candidateWords count] == 1 && [[candidateWords firstObject] caseInsensitiveCompare:partialWord] == NSOrderedSame) {
        return @[];
    }

    return [candidateWords array];
}


// ------------------------------------------------------
/// text did edit.
- (void)textDidChange:(nonnull NSNotification *)aNotification
// ------------------------------------------------------
{
    // 全テキストを再カラーリング
    [[self editorWrapper] setupColoringTimer];

    // アウトラインメニュー項目更新
    [[self editorWrapper] setupOutlineMenuUpdateTimer];
    
    // 非互換文字リスト更新
    [[[self window] windowController] updateIncompatibleCharsIfNeeded];

    // フラグが立っていたら、入力補完を再度実行する
    // （フラグは CETextView > insertCompletion:forPartialWordRange:movement:isFinal: で立てている）
    if ([[self textView] needsRecompletion]) {
        [[self textView] setNeedsRecompletion:NO];
        [[self textView] completeAfterDelay:0.05];
    }
}


// ------------------------------------------------------
/// the selection of main textView was changed.
- (void)textViewDidChangeSelection:(nonnull NSNotification *)aNotification
// ------------------------------------------------------
{
    // highlight the current line
    [self highlightCurrentLine];

    // update document information
    [[[self window] windowController] setupEditorInfoUpdateTimer];

    // update selected item of the outline menu
    [self updateOutlineMenuSelection];

    // highlight matching brace
    
    // The following part is based on Smultron's SMLTextView.m by Peter Borg. (2006-09-09)
    // Smultron 2 was distributed on <http://smultron.sourceforge.net> under the terms of the BSD license.
    // Copyright (c) 2004-2006 Peter Borg

    if (![[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultHighlightBracesKey]) { return; }
    
    NSString *completeString = [[self textView] string];
    if ([completeString length] == 0) { return; }
    
    NSInteger location = [[self textView] selectedRange].location;
    NSInteger difference = location - [self lastCursorLocation];
    [self setLastCursorLocation:location];

    // The brace will be highlighted only when the cursor moves forward, just like on Xcode. (2006-09-10)
    if (difference != 1) {
        return; // If the difference is more than one, they've moved the cursor with the mouse or it has been moved by resetSelectedRange below and we shouldn't check for matching braces then.
    }
    
    // check the caracter just before the cursor
    location--;
    
    unichar beginBrace, endBrace;
    switch ([completeString characterAtIndex:location]) {
        case ')':
            beginBrace = '(';
            endBrace = ')';
            break;
            
        case '}':
            beginBrace = '{';
            endBrace = '}';
            break;
            
        case ']':
            beginBrace = '[';
            endBrace = ']';
            break;
            
        case '>':
            if (![[NSUserDefaults standardUserDefaults] boolForKey:CEDefaultHighlightLtGtKey]) { return; }
            beginBrace = '<';
            endBrace = '>';
            break;
            
        default:
            return;
    }
    
    NSUInteger skippedBraceCount = 0;

    while (location--) {
        unichar character = [completeString characterAtIndex:location];
        if (character == beginBrace) {
            if (!skippedBraceCount) {
                // highlight the matching brace
                [[self textView] showFindIndicatorForRange:NSMakeRange(location, 1)];
                return;
            } else {
                skippedBraceCount--;
            }
        } else if (character == endBrace) {
            skippedBraceCount++;
        }
    }
    
    // do not beep when the typed brace is `>`
    //  -> Since `>` (and `<`) can often be used alone unlike other braces.
    if (endBrace != '>') {
        NSBeep();
    }
}


// ------------------------------------------------------
/// font is changed
- (void)textViewDidChangeTypingAttributes:(nonnull NSNotification *)notification
// ------------------------------------------------------
{
    [self highlightCurrentLine];
}



#pragma mark Notifications

//=======================================================
// Notification  < CETextFinder
//=======================================================

// ------------------------------------------------------
/// did Replace All
- (void)textDidReplaceAll:(nonnull NSNotification *)aNotification
// ------------------------------------------------------
{
    // 文書情報更新（選択範囲・キャレット位置が変更されないまま全置換が実行された場合への対応）
    [[[self window] windowController] setupEditorInfoUpdateTimer];
    
    // 全テキストを再カラーリング
    [[self editorWrapper] setupColoringTimer];
    
    // アウトラインメニュー項目更新
    [[self editorWrapper] setupOutlineMenuUpdateTimer];
    
    // 非互換文字リスト更新
    [[[self window] windowController] updateIncompatibleCharsIfNeeded];
}


//=======================================================
// Notification  < CEThemeManager
//=======================================================

// ------------------------------------------------------
/// テーマが更新された
- (void)themeDidUpdate:(nonnull NSNotification *)notification
// ------------------------------------------------------
{
    if ([[notification userInfo][CEOldNameKey] isEqualToString:[[[self textView] theme] name]]) {
        CETheme *theme = [CETheme themeWithName:[notification userInfo][CENewNameKey]];
        
        if (!theme) { return; }
        
        [[self textView] setTheme:theme];
        [[self textView] setSelectedRanges:[[self textView] selectedRanges]];  // 現在行のハイライトカラーの更新するために選択し直す
        [[self editorWrapper] invalidateSyntaxColoring];
    }
}



#pragma mark Private Mthods

// ------------------------------------------------------
/// return shared sytnaxParser
- (nullable CESyntaxParser *)syntaxParser
// ------------------------------------------------------
{
    return [[self editorWrapper] syntaxParser];
}


// ------------------------------------------------------
/// アウトラインメニューの選択項目を更新
- (void)updateOutlineMenuSelection
// ------------------------------------------------------
{
    if ([[self textView] needsUpdateOutlineMenuItemSelection]) {
        [[self navigationBar] selectOutlineMenuItemWithRange:[[self textView] selectedRange]];
    } else {
        [[self textView] setNeedsUpdateOutlineMenuItemSelection:YES];
        [[self navigationBar] updatePrevNextButtonEnabled];
    }
}


// ------------------------------------------------------
/// テキストビュー分割削除ボタンの有効化／無効化を制御
- (void)updateCloseSplitViewButton:(BOOL)isEnabled
// ------------------------------------------------------
{
    [[self navigationBar] setCloseSplitButtonEnabled:isEnabled];
}


// ------------------------------------------------------
/// カレント行をハイライト表示
- (void)highlightCurrentLine
// ------------------------------------------------------
{
    if (![self highlightsCurrentLine]) { return; }
    
    // 最初に（表示前に） TextView にテキストをセットした際にムダに演算が実行されるのを避ける (2014-07 by 1024jp)
    if (![[self window] isVisible]) { return; }
    
    NSLayoutManager *layoutManager = [[self textView] layoutManager];
    CETextView *textView = [self textView];
    NSRect rect;
    
    // 選択行の矩形を得る
    if ([textView selectedRange].location == [[textView string] length] && [layoutManager extraLineFragmentTextContainer]) {  // 最終行
        rect = [layoutManager extraLineFragmentRect];
        
    } else {
        NSRange lineRange = [[textView string] lineRangeForRange:[textView selectedRange]];
        lineRange.length -= (lineRange.length > 0) ? 1 : 0;  // remove line ending
        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:lineRange actualCharacterRange:NULL];
        
        rect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:[textView textContainer]];
        rect.size.width = [[textView textContainer] containerSize].width;
    }
    
    // 周囲の空白の調整
    CGFloat padding = [[textView textContainer] lineFragmentPadding];
    rect.origin.x = padding;
    rect.size.width -= 2 * padding;
    rect = NSOffsetRect(rect, [textView textContainerOrigin].x, [textView textContainerOrigin].y);
    
    // ハイライト矩形を描画
    if (!NSEqualRects([textView highlightLineRect], rect)) {
        // clear previous highlihght
        [textView setNeedsDisplayInRect:[textView highlightLineRect] avoidAdditionalLayout:YES];
        
        // draw highlight
        [textView setHighlightLineRect:rect];
        [textView setNeedsDisplayInRect:rect avoidAdditionalLayout:YES];
    }
}

@end
