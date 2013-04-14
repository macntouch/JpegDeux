//
//  Master.m
//  JPEGDeux
//
//  Created by Peter on Tue Sep 04 2001.
//

#import "Master.h"
#import "SlideShow.h"
#import "WindowShow.h"
#import "ScreenShow.h"
#import "DockShow.h"
//#import "FSQTShow.h"
#import "DirectDisplayShow.h"
#import "MutableArrayCategory.h"
#import "StringAdditions.h"
#import "ObjectAdditions.h"
#import "DictionaryConvenience.h"
#import "FileHierarchySupport.h"
#import "BackgroundImageView.h"
#import "MasterOutlineStuff.h"
#import <Carbon/Carbon.h>
#import "sorting.h"
#import "ImageWindowController.h"
#import "DefaultTransitionChooser.h"

NSString* const CancelShowException=@"CancelShow";

const static int numShowTypes=5;

const short StopSlideshowEventType=15;

static NSData* archive(NSColor* c) {
    if (! c) c = [NSColor blackColor];
    return [NSArchiver archivedDataWithRootObject:c];
}

static NSColor* unarchive(NSData* data) {
    if (! data) return [NSColor blackColor];
    else return [NSUnarchiver unarchiveObjectWithData:data];
}

#define MINQUALITY 1
#define MAXQUALITY 5

static Master* sharedMaster;
static NSApplication* application;

static NSMutableArray* aliasIfNecessary(NSArray* array) {
    NSUserDefaults* prefs=[NSUserDefaults standardUserDefaults];
    if (! [prefs boolForKey:@"DontAliasDictionaries"]) {
        unsigned i, max=[array count];
        NSMutableArray* a=[NSMutableArray arrayWithCapacity:max];
        for (i=0; i<max; i++) {
            [a addObject:[[array objectAtIndex:i] alias]];
        }
        return a;
    }
    else return [NSMutableArray arrayWithArray:array];
}

static NSMutableArray* unaliasIfNecessary(NSArray* array) {
    if ([array count] && [array isAliased]) {
        unsigned i, max=[array count];
        NSMutableArray* a=[NSMutableArray arrayWithCapacity:max];
        for (i=0; i<max; i++) {
            [a addObject:[[array objectAtIndex:i] unalias]];
        }
        return a;
    }
    else return [NSMutableArray arrayWithArray:array];
}


@implementation Master

+ (Master*)master {
    return sharedMaster;
}

- (void)loadTransitionChooser {
    Class class;
    [myTransitionChooser autorelease];
    class=[DefaultTransitionChooser classForShowTypeByTag:[myDisplayModeClass tagNumber]];
    myTransitionChooser=[[class loadView] retain];
    [myTransitionDrawer setContentView:[myTransitionChooser view]];
}

- (id)init {
    if (self=[super init]) {
        sharedMaster=self;
        application=[NSApplication sharedApplication];
        myDisplayModeClass=[WindowShow class];
        [[NSApplication sharedApplication] setDelegate:self];
        myFileHierarchyArray=[[NSMutableArray alloc] init];
        myUndoer=[[NSUndoManager alloc] init];
        [self loadTransitionChooser];
    }
    return self;
}

- (void)dealloc {
    [myUndoer release];
    [myFileHierarchyArray release];
    [super dealloc];
}

- (void)showWindow {
    [myWindow makeKeyAndOrderFront:self];
}

- (void)synchronizeWindowWithValues {
    [self showWindow];
    [myDisplayModeMatrix selectCellWithTag:[myDisplayModeClass tagNumber]];
    [myShouldLoopButton setIntValue:myShouldLoop];
    [myShouldRandomizeButton setIntValue:myShouldRandomize];
    [myTimeIntervalField setFloatValue:myTimeInterval];
    [myShouldAutoAdvanceButton setIntValue:myShouldAutoAdvance];
    [myScalingMatrix selectCellWithTag:myScaling];
    [myShouldOnlyScaleDownButton setIntValue:myShouldOnlyScaleDown];
    [myDisplayFileNameMatrix selectCellWithTag:myFileNameDisplay];
    [myQualitySlider setFloatValue:myQuality];
    [myShouldPrecacheButton setIntValue:myShouldPrecache];
    [myShouldRecursivelyScanSubdirectoriesButton setIntValue:myShouldRecursivelyScanSubdirectories];
    //if ([myDisplayModeClass inheritsFromClass:[QuicktimeShow class]]) [myQualitySlider setEnabled:YES];
    //else [myQualitySlider setEnabled:NO];
	[myQualitySlider setEnabled:NO];
    [myFilesTable reloadData];
    [myPreview setImageScaling:myScaling];
    [myDisplayCommentButton setIntValue:myCommentDisplay];
    [myPreview setNeedsDisplay:YES];
}

- (NSDictionary*)getSavingDictionary {
    //returns an NSDictionary suitable for saving as a property list
    NSMutableDictionary* dict=[NSMutableDictionary dictionaryWithCapacity:11];
    [dict setBool:myShouldLoop forKey:@"ShouldLoop"];
    [dict setBool:myShouldRandomize forKey:@"ShouldRandom"];
    [dict setFloat:myTimeInterval forKey:@"TimeInterval"];
    [dict setInt:[myDisplayModeClass tagNumber] forKey:@"DisplayMode"];
    [dict setBool:myShouldAutoAdvance forKey:@"ShouldAutoAdvance"];
    [dict setInt:myScaling forKey:@"ScalingMode"];
    [dict setBool:myShouldOnlyScaleDown forKey:@"ShouldOnlyScaleDown"];
    [dict setInt:myFileNameDisplay forKey:@"FileNameDisplayType"];
    [dict setBool:myShouldRecursivelyScanSubdirectories forKey:@"ShouldRecursivelyScanSubdirectories"];
    [dict setBool:myShouldPrecache forKey:@"PreloadImages"];
    [dict setInt:myQuality forKey:@"ImageQuality"];
//    [dict setObject:aliasIfNecessary(myFileHierarchyArray) forKey:@"ChosenFiles"];
    [dict setObject:archive(myBackgroundColor) forKey:@"BackgroundColor"];
    [dict setInt:myCommentDisplay forKey:@"CommentDisplay"];
    [dict setObject:[myTransitionChooser valueDictionary] forKey:@"TransitionValues"];
    return dict;
}

- (void)loadFromDictionary:(NSDictionary*)dict {
    int tag;
    NSArray* oldFiles;
    const id classes[]={[WindowShow class], [ScreenShow class], [DockShow class], [DirectDisplayShow class]};
    myShouldLoop=[dict boolForKey:@"ShouldLoop"];
    myShouldRandomize=[dict boolForKey:@"ShouldRandom"];
    myTimeInterval=[dict floatForKey:@"TimeInterval"];
    tag=[dict intForKey:@"DisplayMode"];
    myDisplayModeClass=classes[tag%numShowTypes];
    myShouldAutoAdvance=[dict boolForKey:@"ShouldAutoAdvance"];
    myScaling=[dict intForKey:@"ScalingMode"];
    myShouldOnlyScaleDown=[dict boolForKey:@"ShouldOnlyScaleDown"];
    myFileNameDisplay=[dict intForKey:@"FileNameDisplayType"];
    myShouldRecursivelyScanSubdirectories=[dict boolForKey:@"ShouldRecursivelyScanSubdirectories"];
    myShouldPrecache=[dict boolForKey:@"PreloadImages"];
    myQuality=[dict intForKey:@"ImageQuality"];
    myCommentDisplay=[dict intForKey:@"CommentDisplay"];
    if (myQuality < MINQUALITY || myQuality > MAXQUALITY) myQuality=MINQUALITY;
    [myFileHierarchyArray release];
    oldFiles=[dict objectForKey:@"ChosenFiles"];
    myBackgroundColor=[unarchive([dict objectForKey:@"BackgroundColor"]) retain];
//    if (! oldFiles) myFileHierarchyArray=[[NSMutableArray alloc] init];
//    else myFileHierarchyArray=[[NSMutableArray alloc] initWithArray:unaliasIfNecessary(oldFiles)];
    myFileHierarchyArray=[[NSMutableArray alloc] init];
    [self loadTransitionChooser];
    [self synchronizeWindowWithValues];
}

- (void)awakeFromNib {
    NSUserDefaults* prefs=[NSUserDefaults standardUserDefaults];
    NSDictionary* prefsDict=[prefs objectForKey:@"LastSlideshow"];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(noteSavePreferences:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];
    if (prefsDict) [self loadFromDictionary:prefsDict];
    if ([prefs boolForKey:@"PreviewDrawerIsOpen"])
        [myDrawer performSelector:@selector(open:) withObject:nil afterDelay:0];

    [myFilesTable setTarget:self];
    [myFilesTable setDoubleAction:@selector(displayImageInWindow:)];
}

- (IBAction)selectFiles:(id)sender {
    NSUserDefaults* defaults=[NSUserDefaults standardUserDefaults];
    NSString* startingDirectory=[defaults stringForKey:@"DefaultImageDirectory"];
    NSString* startingFile=[defaults stringForKey:@"DefaultImageFile"];
    NSOpenPanel* panel=[NSOpenPanel openPanel];
    [self showWindow];
    if (! startingDirectory) startingDirectory=NSHomeDirectory();
    [panel setAllowsMultipleSelection:YES];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:YES];
    [panel beginSheetForDirectory:startingDirectory
                             file:startingFile
                            types:[NSImage imageFileTypes]
                   modalForWindow:[myFilesTable window]
                    modalDelegate:self
                   didEndSelector:@selector(openPanelDidEnd: returnCode: contextInfo:)
                      contextInfo:nil];
}

- (void)openPanelDidEnd:(NSOpenPanel*)panel returnCode:(int)returnCode contextInfo:(void*)contextInfo {
    NSUserDefaults* defaults=[NSUserDefaults standardUserDefaults];
    if (returnCode == NSOKButton) {
        NSArray* filesToOpen = [panel filenames];
        if ([filesToOpen count] > 0) {
            [defaults setObject:[[filesToOpen objectAtIndex:0] stringByDeletingLastPathComponent] forKey:@"DefaultImageDirectory"];
            [defaults setObject:[[filesToOpen objectAtIndex:0] lastPathComponent] forKey:@"DefaultImageFile"];
            [defaults synchronize];
        }
        [self processAndAddFiles:filesToOpen];
        //[myFilesTable collapseItem:nil collapseChildren:YES];
    }
}

- (void)processAndAddURLs:(NSArray*)urls {
    unsigned i, max=[urls count];
    [self saveUndoableState];
    for (i=0; i<max; i++) {
        [myFileHierarchyArray addObject:[urls objectAtIndex:i]];
    }
    [myFilesTable reloadData];
}

- (void)processAndAddFiles:(NSArray*)files {
    //[myChosenFiles mergeWithArray:[self prepareFilesAndDirectories:files]];
    unsigned i, max=[files count];
    [self saveUndoableState];
    for (i=0; i<max; i++) {
        id fileHierarchy=[FileHierarchy hierarchyWithPath:[files objectAtIndex:i]];
        [myFileHierarchyArray addObject:fileHierarchy];
    }
    [myFilesTable reloadData];
}

- (IBAction)setDisplayMode:(id)sender {
    const id classes[]={[WindowShow class], [ScreenShow class], [DockShow class], [DirectDisplayShow class]};
    myDisplayModeClass=classes[[[sender selectedCell] tag]%numShowTypes]; // for paranoia
    //if ([myDisplayModeClass inheritsFromClass:[QuicktimeShow class]]) [myQualitySlider setEnabled:YES];
    //else [myQualitySlider setEnabled:NO];
	[myQualitySlider setEnabled:NO];
    [self loadTransitionChooser];
}

- (IBAction)setLoop:(id)sender {
    myShouldLoop=[sender intValue];
}

- (IBAction)setRandomOrder:(id)sender {
    myShouldRandomize=[sender intValue];
}

- (IBAction)setAutoAdvance:(id)sender {
    myShouldAutoAdvance=[sender intValue];
}

- (IBAction)setInterval:(id)sender {
    myTimeInterval=[sender doubleValue];
}

- (IBAction)setImageScaling:(id)sender {
    myScaling=[[sender selectedCell] tag]%3; //paranoia
    [myPreview setImageScaling:myScaling];
    [myPreview setNeedsDisplay:YES];
}

- (IBAction)setShouldOnlyScaleDown:(id)sender {
    myShouldOnlyScaleDown=[sender intValue];
}

- (IBAction)setShouldRecursivelyScanSubdirectories:(id)sender {
    myShouldRecursivelyScanSubdirectories=[sender intValue];
}

- (IBAction)setFileNameDisplayType:(id)sender {
    myFileNameDisplay=[[sender selectedCell] tag]%3; //paranoia
    [self redoPreviewImageName];
}

- (IBAction)setBackgroundColor:(id)sender {
    [myBackgroundColor release];
    myBackgroundColor=[[sender color] retain];
    [myPreview setColor:myBackgroundColor];
    //[myPreview setNeedsDisplay:YES];
}

- (IBAction)setQualitySlider:(id)sender {
    myQuality=[sender intValue];
}

- (IBAction)setShouldPrecache:(id)sender {
    myShouldPrecache=[sender intValue];
}

- (IBAction)setCommentDisplay:(id)sender {
    myCommentDisplay=[sender intValue];
}

- (void)openSlideshow:(NSString*)path {
    NSDictionary* dict=[NSDictionary dictionaryWithContentsOfFile:path];
    if (! dict) NSBeep();
    else {
        [self loadFromDictionary:dict];
        [myCurrentSavingPath release];
        myCurrentSavingPath=[path copy];
        [[NSDocumentController sharedDocumentController]
            noteNewRecentDocumentURL:[NSURL fileURLWithPath:path]];
    }
}

- (IBAction)openDocument:(id)sender {
    NSOpenPanel* panel=[NSOpenPanel openPanel];
    NSUserDefaults* prefs=[NSUserDefaults standardUserDefaults];
    int result;
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setResolvesAliases:YES];
    [panel setAllowsMultipleSelection:NO];
    result=[panel runModalForDirectory:[prefs objectForKey:@"DefaultSlideshowDirectory"]
                                  file:nil
                                 types:nil];
    if (result==NSOKButton) [self openSlideshow:[[panel filenames] objectAtIndex:0]];
}

- (IBAction)saveDocument:(id)sender {
    NS_DURING
        if (! myCurrentSavingPath) [self saveDocumentAs:sender];
        else {
            NSFileManager* filer=[NSFileManager defaultManager];
            if (! [[self getSavingDictionary] writeToFile:myCurrentSavingPath atomically:YES])
                [NSException raise:@"SaveException"
                            format:@"JPEGDeux couldn't write to the path %@", myCurrentSavingPath];
            else {
                NSNumber* newCreator;
                NSDictionary* attribs;
                newCreator=[NSNumber numberWithUnsignedLong:gCreatorCode];
                attribs=[NSDictionary dictionaryWithObjectsAndKeys:
                    newCreator, NSFileHFSCreatorCode,
                    newCreator, NSFileHFSTypeCode,
                    nil];
                if (! [filer changeFileAttributes:attribs atPath:myCurrentSavingPath])
                    [NSException raise:@"SaveException"
                                format:@"JPEGDeux couldn't change the type/creator code of the saved file"];
            }
            [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:myCurrentSavingPath]];
        }
    NS_HANDLER
        NSRunAlertPanel(@"Error saving file", [localException reason], @"Crud", nil, nil);
    NS_ENDHANDLER
}

- (IBAction)saveDocumentAs:(id)sender {
    NSSavePanel* panel=[NSSavePanel savePanel];
    int result;
    result=[panel runModal];
    if (result==NSFileHandlingPanelOKButton) {
        [myCurrentSavingPath release];
        myCurrentSavingPath=[[panel filename] copy];
        [self saveDocument:sender];
    }
}

- (IBAction)begin:(id)sender {
    NSMutableArray* arr=[[NSMutableArray alloc] init];
    unsigned i, max=[myFileHierarchyArray count];
    for (i=0; i<max; i++) [arr addObjectsFromArray:[FileHierarchy flattenHierarchy:[myFileHierarchyArray objectAtIndex:i]]];
    myChosenFiles=arr;
    if ([myChosenFiles count]==0) {
        NSBeep();
        return;
    }
    myTimeInterval=[myTimeIntervalField doubleValue]; //the IBAction seems unreliable
    [self savePreferenceSettings];
    [myCurrentShow release];
    myCurrentShow=[[myDisplayModeClass alloc] initWithParams:[myTransitionChooser valueDictionary]];
    NS_DURING
    if (myShouldOnlyScaleDown && myScaling==NSScaleProportionally) [myCurrentShow setImageScaling:ScaleDownProportionally];
    else if (myShouldOnlyScaleDown && myScaling==NSScaleToFit) [myCurrentShow setImageScaling:ScaleDownToFit];
    else [myCurrentShow setImageScaling:myScaling];
    [myCurrentShow setCommentStyle:myCommentDisplay];
    [myCurrentShow setFileNameDisplayType:myFileNameDisplay];
    [myCurrentShow beginShow:myChosenFiles];
    [myCurrentShow setQuality:myQuality];
    [myCurrentShow setBackgroundColor:myBackgroundColor];
    if (myShouldPrecache) [(id)myCurrentShow preload];
    NS_HANDLER
        [myCurrentShow release];
        myCurrentShow=nil;
        [myChosenFiles release];
        myChosenFiles=nil;
        return;
    NS_ENDHANDLER
    [self displayImageLoop];
    [myCurrentShow release];
    myCurrentShow=nil;
    [myChosenFiles release];
    myChosenFiles=nil;
}

- (void)noteSavePreferences:(NSNotification*)note {
    [self savePreferenceSettings];
}

- (void)savePreferenceSettings {
    NSUserDefaults* prefs=[NSUserDefaults standardUserDefaults];
    NSDictionary* dict=[self getSavingDictionary];
    [prefs setObject:dict forKey:@"LastSlideshow"];
    [prefs setBool:([myDrawer state]==NSDrawerOpenState || [myDrawer state]==NSDrawerOpeningState)
            forKey:@"PreviewDrawerIsOpen"];
    [prefs synchronize];
}

- (void)displayImageLoop {
    NSDate* date;
    NSAutoreleasePool* pool=nil;
    const BOOL drawerIsOpen=([myDrawer state]==NSDrawerOpenState || [myDrawer state]==NSDrawerOpeningState);
    [myWindow orderOut:self];
    date=[NSDate date];
	
    @try {
        do {
            NSEvent* event=nil;
            BOOL shouldContinue=YES;
            [myCurrentShow rewind:-1];
            if (myShouldRandomize) {
				[myCurrentShow reshuffle];
			}

            while (shouldContinue) {
                NSDate* finishDate;
                CFAbsoluteTime timeOfDisplay;
                EventAction action;
                pool=[[NSAutoreleasePool alloc] init];
                shouldContinue=[myCurrentShow advanceImage:&timeOfDisplay];

				action=eNothing;
                if (myShouldAutoAdvance) {
					finishDate=[NSDate dateWithTimeIntervalSinceReferenceDate: myTimeInterval + timeOfDisplay];
				} else {
					finishDate=[NSDate distantFuture];
				}
				
                do {
                    event=[application nextEventMatchingMask: NSAnyEventMask
                                                   untilDate:finishDate
                                                      inMode:NSDefaultRunLoopMode
                                                     dequeue:YES];
                } while (event && !(action=[self handleEvent:event]));
				
                [pool release];
                pool=nil;
                switch (action) {
                    case eStop:
						myShouldLoop=NO;
						shouldContinue=NO;
						break;
                    case ePrev:
                        shouldContinue=YES;
                        break;
                    case eReeval:
                        //pool=[[NSAutoreleasePool alloc] init];
                        //goto reeval;
						break;
                    default: ;//this ought to shut gcc up
                }
            }
        } while (myShouldLoop);
	}
	@catch (NSException *exception) {
		// TODO: handle an exception
		//if (! [[localException name] isEqualToString:CancelShowException]) [localException raise];
	}
	
        //NSLog(@"%f", [[NSDate date] timeIntervalSinceDate:date]); //used for timing shows
        [pool release];
        pool=nil;

        if (drawerIsOpen) [myDrawer close];
        [myWindow makeKeyAndOrderFront:self];
        if (drawerIsOpen) [myDrawer open];
}

- (EventAction)handleEvent:(NSEvent*)event {
    NSEventType type=[event type];
    //NSLog([event description]);
    if (type==NSKeyDown) {
        unichar theChar=[[event characters] characterAtIndex:0];
        id param=NULL;
        SEL sel=[myPrefsManager selectorForKey:theChar withParam:&param];
        if (theChar=='.' && ([event modifierFlags] & NSCommandKeyMask)) return eStop;
        if (sel) return [self intPerformSelector:sel withObject:param];
    }
    else if (type==NSApplicationDefined) {
        if ([event subtype]==StopSlideshowEventType)
            return eStop;
    }
    [application sendEvent:event];
    return eNothing;
}

- (BOOL)application:(NSApplication*)theApplication openFile:(NSString*)filename {
    NSFileManager* filer=[NSFileManager defaultManager];
    NSDictionary* attribs=[filer fileAttributesAtPath:filename traverseLink:YES];
    if ([[attribs objectForKey:NSFileHFSTypeCode] unsignedIntValue] == gSSTypeCode ||
        [[filename pathExtension] caseInsensitiveCompare:@"plist"] == NSOrderedSame ||
        isPropertyList(filename)) {
        [self openSlideshow:filename];
    }
    else [self processAndAddFiles:[NSArray arrayWithObject:filename]];
    return YES;
}

- (void)recursiveSort:(int (*)(id, id, void*))func onArray:(NSMutableArray*)array {
    unsigned i, max;
    NSMutableDictionary* context=[NSMutableDictionary dictionary];
    [array sortUsingFunction:func context:context];
    max=[array count];
    for (i=0; i < max; i++) {
        id object=[array objectAtIndex:i];
        if ([object isFolder]) {
            [self recursiveSort:func onArray:[object contents]];
        }
    }
}

- (void)recursiveSortSelected:(int (*)(id, id, void*))func onArray:(NSMutableArray*)array {
    NSEnumerator* enumer=[myFilesTable selectedRowEnumerator];
    unsigned i, max;
    NSNumber* indexObject;
    BOOL needToDig=NO;
    NSMutableDictionary* context=[NSMutableDictionary dictionary];
    NSMutableArray* newContents=[NSMutableArray array];
    NSMutableArray* modifiedIndices=[NSMutableArray array];
    while ((indexObject=[enumer nextObject])) {
        int index=[indexObject intValue];
        id object=[myFilesTable itemAtRow:index];
        unsigned arrayIndex;
        arrayIndex=[array indexOfObjectIdenticalTo:object];
        if (arrayIndex != NSNotFound) {
            [modifiedIndices addObject:[NSNumber numberWithUnsignedInt:arrayIndex]];
            [newContents addObject:object];
        }
        else needToDig=YES;
    }
    [newContents sortUsingFunction:func context:context];
    max=[modifiedIndices count];
    for (i=0; i < max; i++) {
        unsigned index=[[modifiedIndices objectAtIndex:i] unsignedIntValue];
        [array replaceObjectAtIndex:index withObject:[newContents objectAtIndex:i]];
    }
    if (needToDig) {
        max=[array count];
        for (i=0; i<max; i++) {
            id object=[array objectAtIndex:i];
            if ([object isFolder]) [self recursiveSortSelected:func onArray:[object contents]];
        }
    }
}

- (void)saveUndoableState {
    NSMutableArray* arr=[[myFileHierarchyArray deepMutableCopy] autorelease];
    [myUndoer registerUndoWithTarget:self selector:@selector(undoState:) object:arr];
}

- (void)undoState:(id)object {
    [self saveUndoableState];
    [myFileHierarchyArray autorelease];
    myFileHierarchyArray=[object retain];
    [myFilesTable reloadData];
}

- (BOOL)validateMenuItem:(id)menuItem {
    SEL action=[menuItem action];
    if (action==@selector(closeWindow:)) {
        return [myWindow isVisible];
    }
    else if (action==@selector(undo:)) {
        return [myUndoer canUndo];
    }
    else if (action==@selector(redo:)) {
        return [myUndoer canRedo];
    }
    else return YES;//[super validateMenuItem:menuItem];
}

- (IBAction)undo:(id)sender {
    [myUndoer undo];
}

- (IBAction)redo:(id)sender {
    [myUndoer redo];
}

- (void)sort:(int (*)(id, id, void*))func {
    [self saveUndoableState];
    [self recursiveSort:func onArray:myFileHierarchyArray];
    [myFilesTable reloadData];
}

- (void)sortSelected:(int (*)(id, id, void*))func {
    [self saveUndoableState];
    [self recursiveSortSelected:func onArray:myFileHierarchyArray];
    [myFilesTable reloadData];
}

- (IBAction)sortName:(id)sender {
    [self sort:sortName];
}

- (IBAction)sortNumber:(id)sender {
    [self sort:sortNumber];
}

- (IBAction)sortModified:(id)sender {
    [self sort:sortModified];
}

- (IBAction)sortCreated:(id)sender {
    [self sort:sortCreated];
}

- (IBAction)sortKind:(id)sender {
    [self sort:sortKind];
}

- (IBAction)sortSelectedName:(id)sender {
    [self sortSelected:sortName];
}

- (IBAction)sortSelectedNumber:(id)sender {
    [self sortSelected:sortName];
}

- (IBAction)sortSelectedModified:(id)sender {
    [self sortSelected:sortModified];
}

- (IBAction)sortSelectedCreated:(id)sender {
    [self sortSelected:sortCreated];
}

- (IBAction)sortSelectedKind:(id)sender {
    [self sortSelected:sortKind];
}

- (IBAction)removeAllImages:(id)sender {
    [self showWindow];
    [self saveUndoableState];
    [myFileHierarchyArray removeAllObjects];
    [myFilesTable reloadData];
}

- (IBAction)flattenImageHierarchy:(id)sender {
    NSMutableArray* arr=[[NSMutableArray alloc] init];
    unsigned i, max=[myFileHierarchyArray count];
    [self showWindow];
    for (i=0; i<max; i++)
        [arr addObjectsFromArray:[FileHierarchy flattenHierarchy:[myFileHierarchyArray objectAtIndex:i]]];
    [self saveUndoableState];
    [myFileHierarchyArray autorelease];
    myFileHierarchyArray=arr;
    [myFilesTable reloadData];
}

- (void)recursiveReverseAll:(NSMutableArray*)array {
    unsigned i, max;
    [array reverse];
    max=[array count];
    for (i=0; i < max; i++) {
        id object=[array objectAtIndex:i];
        if ([object isFolder]) {
            [self recursiveReverseAll:[object contents]];
        }
    }
}

- (void)recursiveReverseSelected:(NSMutableArray*)array {
    NSEnumerator* enumer=[myFilesTable selectedRowEnumerator];
    unsigned i, max;
    NSNumber* indexObject;
    BOOL needToDig=NO;
    NSMutableArray* newContents=[NSMutableArray array];
    NSMutableArray* modifiedIndices=[NSMutableArray array];
    while ((indexObject=[enumer nextObject])) {
        int index=[indexObject intValue];
        id object=[myFilesTable itemAtRow:index];
        unsigned arrayIndex;
        arrayIndex=[array indexOfObjectIdenticalTo:object];
        if (arrayIndex != NSNotFound) {
            [modifiedIndices addObject:[NSNumber numberWithUnsignedInt:arrayIndex]];
            [newContents insertObject:object atIndex:0];
        }
        else needToDig=YES;
    }
    max=[modifiedIndices count];
    for (i=0; i < max; i++) {
        unsigned index=[[modifiedIndices objectAtIndex:i] unsignedIntValue];
        [array replaceObjectAtIndex:index withObject:[newContents objectAtIndex:i]];
    }
    if (needToDig) {
        max=[array count];
        for (i=0; i<max; i++) {
            id object=[array objectAtIndex:i];
            if ([object isFolder]) [self recursiveReverseSelected:[object contents]];
        }
    }
}

- (IBAction)reverseAllImages:(id)sender {
    [self showWindow];
    [self saveUndoableState];
    [self recursiveReverseAll:myFileHierarchyArray];
    [myFilesTable reloadData];
}

- (IBAction)reverseSelectedImages:(id)sender {
    [self showWindow];
    [self saveUndoableState];
    [self recursiveReverseSelected:myFileHierarchyArray];
    [myFilesTable reloadData];
}

- (IBAction)displayImageInWindow:(id)sender {
    int row=[myFilesTable selectedRow];
    if (row > -1) {
        id hierarchy=[myFilesTable itemAtRow:row];
        if (hierarchy!=nil && ![hierarchy isFolder]) {
            [ImageWindowController controllerForPath:hierarchy];
        }
    }
}

- (IBAction)closeWindow:(id)sender {
    [myWindow orderOut:self];
}

@end