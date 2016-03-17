/*
 
 CESyntaxEditSheetController.m
 
 CotEditor
 http://coteditor.com
 
 Created by 1024jp on 2014-04-03.

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

#import "CESyntaxEditSheetController.h"
#import "CESyntaxManager.h"
#import "Constants.h"


typedef NS_ENUM(NSUInteger, CETabIndex) {
    KeywordsTab,
    CommandsTab,
    TypesTab,
    AttributesTab,
    VariablesTab,
    ValuesTab,
    NumbersTab,
    StringsTab,
    CharactersTab,
    CommentsTab,
    
    OutlineTab     = 11,
    CompletionTab  = 12,
    FileMappingTab = 13,
    
    StyleInfoTab   = 15,
    ValidationTab  = 16,
};


@interface CESyntaxEditSheetController () <NSTextFieldDelegate, NSTableViewDelegate>

@property (nonatomic, nonnull) NSMutableDictionary<NSString *, id> *style;  // スタイル定義（NSArrayControllerを通じて操作）
@property (nonatomic) CESyntaxEditSheetMode mode;
@property (nonatomic, nonnull, copy) NSString *originalStyleName;   // シートを生成した際に指定したスタイル名
@property (nonatomic, getter=isStyleNameValid) BOOL styleNameValid;
@property (nonatomic, getter=isBundledStyle) BOOL bundledStyle;

@property (nonatomic, nullable, weak) IBOutlet NSTableView *menuTableView;
@property (nonatomic, nullable, weak) IBOutlet NSTextField *styleNameField;
@property (nonatomic, nullable, weak) IBOutlet NSTextField *messageField;
@property (nonatomic, nullable, weak) IBOutlet NSButton *factoryDefaultsButton;
@property (nonatomic, nullable, strong) IBOutlet NSTextView *validationTextView;  // on 10.8 NSTextView cannot be weak

@property (nonatomic) NSUInteger selectedDetailTag; // Elementsタブでのポップアップメニュー選択用バインディング変数(#削除不可)

@end




#pragma mark -

@implementation CESyntaxEditSheetController

#pragma mark Superclass Methods

// ------------------------------------------------------
/// initialize
- (nullable instancetype)initWithStyle:(nonnull NSString *)styleName mode:(CESyntaxEditSheetMode)mode
// ------------------------------------------------------
{
    self = [super initWithWindowNibName:@"SyntaxEditSheet"];
    if (self) {
        NSMutableDictionary<NSString *, id> *style;
        NSString *name;
        
        switch (mode) {
            case CECopySyntaxEdit:
                style = [[[CESyntaxManager sharedManager] styleWithStyleName:styleName] mutableCopy];
                name = [[CESyntaxManager sharedManager] copiedStyleName:styleName];
                break;
                
            case CENewSyntaxEdit:
                style = [[[CESyntaxManager sharedManager] emptyStyle] mutableCopy];
                name = @"";
                break;
                
            case CESyntaxEdit:
                style = [[[CESyntaxManager sharedManager] styleWithStyleName:styleName] mutableCopy];
                name = styleName;
                break;
        }
        if (!name) { return nil; }
        
        _mode = mode;
        _originalStyleName = name;
        _style = style;
        _styleNameValid = YES;
        _bundledStyle = [[CESyntaxManager sharedManager] isBundledStyle:name];
    }
    
    return self;
}


// ------------------------------------------------------
/// setup UI
- (void)windowDidLoad
// ------------------------------------------------------
{
    [super windowDidLoad];
    
    NSString *styleName = [self originalStyleName];
    BOOL isDefaultSyntax = [[CESyntaxManager sharedManager] isBundledStyle:styleName];
    
    [[self styleNameField] setStringValue:styleName];
    [[self styleNameField] setDrawsBackground:!isDefaultSyntax];
    [[self styleNameField] setBezeled:!isDefaultSyntax];
    [[self styleNameField] setSelectable:!isDefaultSyntax];
    [[self styleNameField] setEditable:!isDefaultSyntax];
    
    if (isDefaultSyntax) {
        BOOL isEqual = [[CESyntaxManager sharedManager] isEqualToBundledStyle:[self style] name:styleName];
        [[self styleNameField] setBordered:YES];
        [[self messageField] setStringValue:NSLocalizedString(@"Bundled styles can’t be renamed.", nil)];
        [[self factoryDefaultsButton] setEnabled:!isEqual];
    } else {
        [[self messageField] setStringValue:@""];
        [[self factoryDefaultsButton] setEnabled:NO];
    }
}



#pragma mark Delegate

//=======================================================
// NSTextFieldDelegate  < styleNameField
//=======================================================

// ------------------------------------------------------
/// スタイル名が変更された
- (void)controlTextDidChange:(nonnull NSNotification *)aNotification
// ------------------------------------------------------
{
    // 入力されたスタイル名の検証
    if ([aNotification object] == [self styleNameField]) {
        NSString *styleName = [[self styleNameField] stringValue];
        styleName = [styleName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [self validateStyleName:styleName];
    }
}


//=======================================================
// NSTableViewDelegate  < menuTableView
//=======================================================

// ------------------------------------------------------
/// tableView の選択が変更された
- (void)tableViewSelectionDidChange:(nonnull NSNotification *)notification
// ------------------------------------------------------
{
    NSTableView *tableView = [notification object];
    NSInteger row = [tableView selectedRow];
    
    // switch view
    [self setSelectedDetailTag:row];
}


// ------------------------------------------------------
/// 行を選択するべきかを返す
- (BOOL)tableView:(nonnull NSTableView *)tableView shouldSelectRow:(NSInteger)row
// ------------------------------------------------------
{
    // セパレータは選択不可
    return ![[self menuTitles][row] isEqualToString:CESeparatorString];
}



#pragma mark Action Messages

// ------------------------------------------------------
/// スタイルの内容を出荷時設定に戻す
- (IBAction)setToFactoryDefaults:(nullable id)sender
// ------------------------------------------------------
{
    NSMutableDictionary<NSString *, id> *style = [[[CESyntaxManager sharedManager] bundledStyleWithStyleName:[self originalStyleName]] mutableCopy];
    
    if (!style) { return; }
    
    // フォーカスを移しておく
    [[sender window] makeFirstResponder:[sender window]];
    // 内容をセット
    [self setStyle:style];
    // デフォルト設定に戻すボタンを無効化
    [[self factoryDefaultsButton] setEnabled:NO];
}


// ------------------------------------------------------
/// カラーシンタックス編集シートの OK ボタンが押された
- (IBAction)saveEdit:(nullable id)sender
// ------------------------------------------------------
{
    // フォーカスを移して入力中の値を確定
    [[sender window] makeFirstResponder:sender];
    
    // style名から先頭または末尾のスペース／タブ／改行を排除
    NSString *styleName = [[[self styleNameField] stringValue]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    [[self styleNameField] setStringValue:styleName];
    
    // style名のチェック
    NSString *errorMessage = [self validateStyleName:styleName];
    if (errorMessage) {
        NSBeep();
        [[[self styleNameField] window] makeFirstResponder:[self styleNameField]];
        return;
    }
    
    // エラー未チェックかつエラーがあれば、表示（エラーを表示していてOKボタンを押下したら、そのまま確定）
    if ([[[self validationTextView] string] isEqualToString:@""] && ([self validate] > 0)) {
        // 「構文要素チェック」を選択
        // （selectItemAtIndex: だとバインディングが実行されないので、メニューを取得して選択している）
        NSBeep();
        [[self menuTableView] selectRowIndexes:[NSIndexSet indexSetWithIndex:ValidationTab] byExtendingSelection:NO];
        return;
    }
    
    [[CESyntaxManager sharedManager] saveStyle:[self style] name:styleName oldName:[self originalStyleName]];
    
    [self endSheetWithReturnCode:NSOKButton];
}


// ------------------------------------------------------
/// カラーシンタックス編集シートの Cancel ボタンが押された
- (IBAction)cancelEdit:(nullable id)sender
// ------------------------------------------------------
{
    [self endSheetWithReturnCode:NSCancelButton];
}


// ------------------------------------------------------
/// 構文チェックを開始
- (IBAction)startValidation:(nullable id)sender
// ------------------------------------------------------
{
    [self validate];
}



#pragma mark Private Mthods

// ------------------------------------------------------
/// メニュー項目を返す
- (nonnull NSArray<NSString *> *)menuTitles
// ------------------------------------------------------
{
    return @[NSLocalizedString(@"Keywords", nil),
             NSLocalizedString(@"Commands", nil),
             NSLocalizedString(@"Types", nil),
             NSLocalizedString(@"Attributes", nil),
             NSLocalizedString(@"Variables", nil),
             NSLocalizedString(@"Values", nil),
             NSLocalizedString(@"Numbers", nil),
             NSLocalizedString(@"Strings", nil),
             NSLocalizedString(@"Characters", nil),
             NSLocalizedString(@"Comments", nil),
             CESeparatorString,
             NSLocalizedString(@"Outline Menu", nil),
             NSLocalizedString(@"Completion List", nil),
             NSLocalizedString(@"File Mapping", nil),
             CESeparatorString,
             NSLocalizedString(@"Style Info", nil),
             NSLocalizedString(@"Syntax Validation", nil)];
}


// ------------------------------------------------------
/// シートを終わる
- (void)endSheetWithReturnCode:(NSInteger)returnCode
// ------------------------------------------------------
{
    if (NSAppKitVersionNumber >= NSAppKitVersionNumber10_9) { // on Mavericks or later
        [[[self window] sheetParent] endSheet:[self window] returnCode:returnCode];
    } else {
        [NSApp stopModal];
        [NSApp endSheet:[self window] returnCode:returnCode];
    }
    [self close];
}


// ------------------------------------------------------
/// 有効なスタイル名かチェックしてエラーメッセージを返す
- (nullable NSString *)validateStyleName:(nonnull NSString *)styleName;
// ------------------------------------------------------
{
    if (([self mode] == CESyntaxEdit) && [[CESyntaxManager sharedManager] isBundledStyle:[self originalStyleName]]) {
        return nil;
    }
    
    NSString *message = nil;
    
    if (([self mode] == CECopySyntaxEdit) || ([self mode] == CENewSyntaxEdit) ||
        (([self mode] == CESyntaxEdit) && ([styleName caseInsensitiveCompare:[self originalStyleName]] != NSOrderedSame)))
    {
        // NSArray を case insensitive に検索するブロック
        __block NSString *duplicatedStyleName;
        BOOL (^caseInsensitiveContains)() = ^(id obj, NSUInteger idx, BOOL *stop){
            BOOL found = ([obj caseInsensitiveCompare:styleName] == NSOrderedSame);
            if (found) { duplicatedStyleName = obj; }
            return found;
        };
        
        if ([styleName length] < 1) {  // 空は不可
            message = NSLocalizedString(@"Input style name.", nil);
        } else if ([styleName rangeOfString:@"/"].location != NSNotFound) {  // ファイル名としても使われるので、"/" が含まれる名前は不可
            message = NSLocalizedString(@"You can’t use a style name that contains “/”. Please choose another name.", nil);
        } else if ([styleName hasPrefix:@"."]) {  // ファイル名としても使われるので、"." から始まる名前は不可
            message = NSLocalizedString(@"You can’t use a style name that begins with a dot “.”. Please choose another name.", nil);
        } else if ([[[CESyntaxManager sharedManager] styleNames] indexOfObjectPassingTest:caseInsensitiveContains] != NSNotFound) {  // 既にある名前は不可
            message = [NSString stringWithFormat:NSLocalizedString(@"“%@” is already taken. Please choose another name.", nil), duplicatedStyleName];
        }
    }
    
    [self setStyleNameValid:(!message)];
    [[self messageField] setStringValue:message ? : @""];
    
    return message;
}


// ------------------------------------------------------
/// 構文チェックを実行しその結果をテキストビューに挿入（戻り値はエラー数）
- (NSUInteger)validate
// ------------------------------------------------------
{
    NSArray<NSDictionary<NSString*, NSString *> *> *results = [[CESyntaxManager sharedManager] validateSyntax:[self style]];
    NSUInteger numberOfErrors = [results count];
    NSMutableString *message = [NSMutableString string];
    
    if (numberOfErrors == 0) {
        [message appendString:NSLocalizedString(@"No error was found.", nil)];
    } else if (numberOfErrors == 1) {
        [message appendString:NSLocalizedString(@"An error was found!", nil)];
    } else {
        [message appendFormat:NSLocalizedString(@"%i errors were found!", nil), numberOfErrors];
    }
    
    for (NSDictionary<NSString*, NSString *> *result in results) {
        [message appendFormat:@"\n\n%@: [%@] %@\n\t> %@",
         result[CESyntaxValidationTypeKey],
         result[CESyntaxValidationRoleKey],
         result[CESyntaxValidationStringKey],
         result[CESyntaxValidationMessageKey]];
    }
    
    [[self validationTextView] setString:message];
    
    return numberOfErrors;
}

@end
