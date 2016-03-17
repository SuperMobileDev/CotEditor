/*
 
 CEDocument+Authopen.m
 
 CotEditor
 http://coteditor.com
 
 Created by 1024jp on 2015-06-29.

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

#import "CEDocument+Authopen.h"


@implementation CEDocument (Authopen)

// ------------------------------------------------------
/// Try reading data at the URL using authopen (Sandobox incompatible)
- (nullable NSData *)forceReadDataFromURL:(nonnull NSURL *)url
// ------------------------------------------------------
{
    NSData *data = nil;
    
    // read data using `authopen` command
    NSString *path = @([[url path] fileSystemRepresentation]);
    NSTask *task = [[NSTask alloc] init];
    
    [task setLaunchPath:@"/usr/libexec/authopen"];
    [task setArguments:@[path]];
    [task setStandardOutput:[NSPipe pipe]];
    
    [task launch];
    data = [NSData dataWithData:[[[task standardOutput] fileHandleForReading] readDataToEndOfFile]];
    
    while ([task isRunning]) {
        usleep(200);
    }
    
    int status = [task terminationStatus];
    BOOL success = (status == 0);
    
    return success ? data : nil;
}


// ------------------------------------------------------
/// Try writing data to the URL using authopen (Sandobox incompatible)
- (BOOL)forceWriteData:(nonnull NSData *)data URL:(nonnull NSURL *)url
// ------------------------------------------------------
{
    // save data using `authopen` command
    NSString *path = @([[url path] fileSystemRepresentation]);
    NSTask *task = [[NSTask alloc] init];
    
    [task setLaunchPath:@"/usr/libexec/authopen"];
    [task setArguments:@[@"-c", @"-w", path]];
    [task setStandardInput:[NSPipe pipe]];
    
    [task launch];
    [[[task standardInput] fileHandleForWriting] writeData:data];
    [[[task standardInput] fileHandleForWriting] closeFile];
    
    // [caution] Do not use `[task waitUntilExit]` here,
    //           since it passes through the run-loop and other file access can interrupt.
    while ([task isRunning]) {
        usleep(200);
    }
    
    int status = [task terminationStatus];
    BOOL success = (status == 0);
    
    return success;
}

@end
