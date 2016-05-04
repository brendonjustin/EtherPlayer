/*****************************************************************************
 * VLCMedia.h: VLCKit.framework VLCMedia header
 *****************************************************************************
 * Copyright (C) 2007 Pierre d'Herbemont
 * Copyright (C) 2013 Felix Paul Kühne
 * Copyright (C) 2007-2013 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Pierre d'Herbemont <pdherbemont # videolan.org>
 *          Felix Paul Kühne <fkuehne # videolan.org>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import <Foundation/Foundation.h>
#import "VLCMediaList.h"
#import "VLCTime.h"

/* Meta Dictionary Keys */
/**
 * Standard dictionary keys for retreiving meta data.
 */
extern NSString *const VLCMetaInformationTitle;          /* NSString */
extern NSString *const VLCMetaInformationArtist;         /* NSString */
extern NSString *const VLCMetaInformationGenre;          /* NSString */
extern NSString *const VLCMetaInformationCopyright;      /* NSString */
extern NSString *const VLCMetaInformationAlbum;          /* NSString */
extern NSString *const VLCMetaInformationTrackNumber;    /* NSString */
extern NSString *const VLCMetaInformationDescription;    /* NSString */
extern NSString *const VLCMetaInformationRating;         /* NSString */
extern NSString *const VLCMetaInformationDate;           /* NSString */
extern NSString *const VLCMetaInformationSetting;        /* NSString */
extern NSString *const VLCMetaInformationURL;            /* NSString */
extern NSString *const VLCMetaInformationLanguage;       /* NSString */
extern NSString *const VLCMetaInformationNowPlaying;     /* NSString */
extern NSString *const VLCMetaInformationPublisher;      /* NSString */
extern NSString *const VLCMetaInformationEncodedBy;      /* NSString */
extern NSString *const VLCMetaInformationArtworkURL;     /* NSString */
extern NSString *const VLCMetaInformationArtwork;        /* NSImage  */
extern NSString *const VLCMetaInformationTrackID;        /* NSString */
extern NSString *const VLCMetaInformationTrackTotal;     /* NSString */
extern NSString *const VLCMetaInformationDirector;       /* NSString */
extern NSString *const VLCMetaInformationSeason;         /* NSString */
extern NSString *const VLCMetaInformationEpisode;        /* NSString */
extern NSString *const VLCMetaInformationShowName;       /* NSString */
extern NSString *const VLCMetaInformationActors;         /* NSString */
extern NSString *const VLCMetaInformationAlbumArtist;    /* NSString */
extern NSString *const VLCMetaInformationDiscNumber;     /* NSString */

/* Notification Messages */
/**
 * Available notification messages.
 */
extern NSString *const VLCMediaMetaChanged;  //< Notification message for when the media's meta data has changed

// Forward declarations, supresses compiler error messages
@class VLCMediaList;
@class VLCMedia;

typedef NS_ENUM(NSInteger, VLCMediaState) {
    VLCMediaStateNothingSpecial,        //< Nothing
    VLCMediaStateBuffering,             //< Stream is buffering
    VLCMediaStatePlaying,               //< Stream is playing
    VLCMediaStateError,                 //< Can't be played because an error occurred
};

/**
 * Informal protocol declaration for VLCMedia delegates.  Allows data changes to be
 * trapped.
 */
@protocol VLCMediaDelegate <NSObject>
// TODO: SubItemAdded/SubItemRemoved implementation.  Not sure if we really want to implement this.
///**
// * Delegate method called whenever a sub item has been added to the specified VLCMedia.
// * \param aMedia The media resource that has received the new sub item.
// * \param childMedia The new sub item added.
// * \param index Location of the new subitem in the aMedia's sublist.
// */
// - (void)media:(VLCMedia *)media addedSubItem:(VLCMedia *)childMedia atIndex:(int)index;

///**
// * Delegate method called whenever a sub item has been removed from the specified VLCMedia.
// * \param aMedia The media resource that has had a sub item removed from.
// * \param childMedia The sub item removed.
// * \param index The previous location of the recently removed sub item.
// */
// - (void)media:(VLCMedia *)aMedia removedSubItem:(VLCMedia *)childMedia atIndex:(int)index;

@optional

/**
 * Delegate method called whenever the media's meta data was changed for whatever reason
 * \note this is called more often than mediaDidFinishParsing, so it may be less efficient
 * \param aMedia The media resource whose meta data has been changed.
 */
- (void)mediaMetaDataDidChange:(VLCMedia *)aMedia;

/**
 * Delegate method called whenever the media was parsed.
 * \param aMedia The media resource whose meta data has been changed.
 */

- (void)mediaDidFinishParsing:(VLCMedia *)aMedia;
@end

/**
 * Defines files and streams as a managed object.  Each media object can be
 * administered seperately.  VLCMediaPlayer or VLCMediaList must be used
 * to execute the appropriate playback functions.
 * \see VLCMediaPlayer
 * \see VLCMediaList
 */
@interface VLCMedia : NSObject

/* Factories */
/**
 * Manufactures a new VLCMedia object using the URL specified.
 * \param anURL URL to media to be accessed.
 * \return A new VLCMedia object, only if there were no errors.  This object will be automatically released.
 * \see initWithMediaURL
 */
+ (instancetype)mediaWithURL:(NSURL *)anURL;

/**
 * Manufactures a new VLCMedia object using the path specified.
 * \param aPath Path to the media to be accessed.
 * \return A new VLCMedia object, only if there were no errors.  This object will be automatically released.
 * \see initWithPath
 */
+ (instancetype)mediaWithPath:(NSString *)aPath;

/**
 * convienience method to return a user-readable codec name for the given FourCC
 * \param uint32_t the FourCC to process
 * \param NSString a VLC track type if known to speed-up the name search
 * \return a NSString containing the codec name if recognized, else an empty string
 */
+ (NSString *)codecNameForFourCC:(uint32_t)fourcc trackType:(NSString *)trackType;

/**
 * TODO
 * \param aName TODO
 * \return a new VLCMedia object, only if there were no errors.  This object
 * will be automatically released.
 * \see initAsNodeWithName
 */
+ (instancetype)mediaAsNodeWithName:(NSString *)aName;

/* Initializers */
/**
 * Initializes a new VLCMedia object to use the specified URL.
 * \param aPath Path to media to be accessed.
 * \return A new VLCMedia object, only if there were no errors.
 */
- (instancetype)initWithURL:(NSURL *)anURL;

/**
 * Initializes a new VLCMedia object to use the specified path.
 * \param aPath Path to media to be accessed.
 * \return A new VLCMedia object, only if there were no errors.
 */
- (instancetype)initWithPath:(NSString *)aPath;

/**
 * TODO
 * \param aName TODO
 * \return A new VLCMedia object, only if there were no errors.
 */
- (instancetype)initAsNodeWithName:(NSString *)aName;

typedef NS_ENUM(NSUInteger, VLCMediaType) {
    VLCMediaTypeUnknown,
    VLCMediaTypeFile,
    VLCMediaTypeDirectory,
    VLCMediaTypeDisc,
    VLCMediaTypeStream,
    VLCMediaTypePlaylist,
};

/**
 * media type
 * \return returns the type of a media (VLCMediaType)
 */
@property (readonly) VLCMediaType mediaType;

/**
 * Returns an NSComparisonResult value that indicates the lexical ordering of
 * the receiver and a given meda.
 * \param media The media with which to compare with the receiver.
 * \return NSOrderedAscending if the URL of the receiver precedes media in
 * lexical ordering, NSOrderedSame if the URL of the receiver and media are
 * equivalent in lexical value, and NSOrderedDescending if the URL of the
 * receiver follows media. If media is nil, returns NSOrderedDescending.
 */
- (NSComparisonResult)compare:(VLCMedia *)media;

/* Properties */
/**
 * Receiver's delegate.
 */
@property (nonatomic, weak) id<VLCMediaDelegate> delegate;

/**
 * A VLCTime object describing the length of the media resource, only if it is
 * available.  Use lengthWaitUntilDate: to wait for a specified length of time.
 * \see lengthWaitUntilDate
 */
@property (nonatomic, readwrite, strong) VLCTime * length;

/**
 * Returns a VLCTime object describing the length of the media resource,
 * however, this is a blocking operation and will wait until the preparsing is
 * completed before returning anything.
 * \param aDate Time for operation to wait until, if there are no results
 * before specified date then nil is returned.
 * \return The length of the media resource, nil if it couldn't wait for it.
 */
- (VLCTime *)lengthWaitUntilDate:(NSDate *)aDate;

/**
 * Determines if the media has already been preparsed.
 */
@property (nonatomic, readonly) BOOL isParsed;

/**
 * The URL for the receiver's media resource.
 */
@property (nonatomic, readonly, strong) NSURL * url;

/**
 * The receiver's sub list.
 */
@property (nonatomic, readonly, strong) VLCMediaList * subitems;

/**
 * get meta property for key
 * \note for performance reasons, fetching the metaDictionary will be faster!
 * \see metaDictionary
 * \see dictionary keys above
 */
- (NSString *)metadataForKey:(NSString *)key;

/**
 * set meta property for key
 * \param metadata to set as NSString
 * \param metadata key
 * \see dictionary keys above
 */
- (void)setMetadata:(NSString *)data forKey:(NSString *)key;

/**
 * Save the previously changed metadata
 * \return true if saving was successful
 */
@property (NS_NONATOMIC_IOSONLY, readonly) BOOL saveMetadata;

/**
 * The receiver's meta data as a NSDictionary object.
 */
@property (nonatomic, readonly, copy) NSDictionary * metaDictionary;

/**
 * The receiver's state, such as Playing, Error, NothingSpecial, Buffering.
 */
@property (nonatomic, readonly) VLCMediaState state;

/**
 * returns a bool whether is the media is expected to play fluently on this
 * device or not. It always returns YES on a Mac.*/
@property (NS_NONATOMIC_IOSONLY, getter=isMediaSizeSuitableForDevice, readonly) BOOL mediaSizeSuitableForDevice;

/**
 * Tracks information NSDictionary Possible Keys
 */

/**
 * \returns a NSNumber
 */
extern NSString *const VLCMediaTracksInformationCodec;

/**
 * \returns a NSNumber
 */
extern NSString *const VLCMediaTracksInformationId;
/**
 * \returns a NSString
 * \see VLCMediaTracksInformationTypeAudio
 * \see VLCMediaTracksInformationTypeVideo
 * \see VLCMediaTracksInformationTypeText
 * \see VLCMediaTracksInformationTypeUnknown
 */
extern NSString *const VLCMediaTracksInformationType;

/**
 * \returns a NSNumber
 */
extern NSString *const VLCMediaTracksInformationCodecProfile;
/**
 * \returns a NSNumber
 */
extern NSString *const VLCMediaTracksInformationCodecLevel;

/**
 * \returns the bitrate as NSNumber
 */
extern NSString *const VLCMediaTracksInformationBitrate;
/**
 * \returns the language as NSString
 */
extern NSString *const VLCMediaTracksInformationLanguage;
/**
 * \returns the description as NSString
 */
extern NSString *const VLCMediaTracksInformationDescription;

/**
 * \returns the audio channel number as NSNumber
 */
extern NSString *const VLCMediaTracksInformationAudioChannelsNumber;
/**
 * \returns the audio rate as NSNumber
 */
extern NSString *const VLCMediaTracksInformationAudioRate;

/**
 * \returns the height as NSNumber
 */
extern NSString *const VLCMediaTracksInformationVideoHeight;
/**
 * \returns the width as NSNumber
 */
extern NSString *const VLCMediaTracksInformationVideoWidth;

/**
 * \returns the source aspect ratio as NSNumber
 */
extern NSString *const VLCMediaTracksInformationSourceAspectRatio;
/**
 * \returns the source aspect ratio denominator as NSNumber
 */
extern NSString *const VLCMediaTracksInformationSourceAspectRatioDenominator;

/**
 * \returns the frame rate as NSNumber
 */
extern NSString *const VLCMediaTracksInformationFrameRate;
/**
 * \returns the frame rate denominator as NSNumber
 */
extern NSString *const VLCMediaTracksInformationFrameRateDenominator;

/**
 * \returns the text encoding as NSString
 */
extern NSString *const VLCMediaTracksInformationTextEncoding;

/**
 * Tracks information NSDictionary values for
 * VLCMediaTracksInformationType
 */
extern NSString *const VLCMediaTracksInformationTypeAudio;
extern NSString *const VLCMediaTracksInformationTypeVideo;
extern NSString *const VLCMediaTracksInformationTypeText;
extern NSString *const VLCMediaTracksInformationTypeUnknown;

/**
 * Returns the tracks information.
 *
 * This is an array of NSDictionary representing each track.
 * It can contain the following keys:
 *
 * \see VLCMediaTracksInformationCodec
 * \see VLCMediaTracksInformationId
 * \see VLCMediaTracksInformationType
 *
 * \see VLCMediaTracksInformationCodecProfile
 * \see VLCMediaTracksInformationCodecLevel
 *
 * \see VLCMediaTracksInformationBitrate
 * \see VLCMediaTracksInformationLanguage
 * \see VLCMediaTracksInformationDescription
 *
 * \see VLCMediaTracksInformationAudioChannelsNumber
 * \see VLCMediaTracksInformationAudioRate
 *
 * \see VLCMediaTracksInformationVideoHeight
 * \see VLCMediaTracksInformationVideoWidth
 *
 * \see VLCMediaTracksInformationSourceAspectRatio
 * \see VLCMediaTracksInformationSourceAspectDenominator
 *
 * \see VLCMediaTracksInformationFrameRate
 * \see VLCMediaTracksInformationFrameRateDenominator
 *
 * \see VLCMediaTracksInformationTextEncoding
 */

@property (NS_NONATOMIC_IOSONLY, readonly, copy) NSArray *tracksInformation;

/**
 * Start asynchronously to parse the media.
 * This will attempt to fetch the meta data and tracks information.
 *
 * This is automatically done when an accessor requiring parsing
 * is called.
 *
 * \see -[VLCMediaDelegate mediaDidFinishParsing:]
 */
- (void)parse;

/**
 * Trigger a synchronous parsing of the media
 * the selector won't return until parsing finished
 */
- (void)synchronousParse;


enum {
    VLCMediaParseLocal          = 0x00,
    VLCMediaParseNetwork        = 0x01,
    VLCMediaFetchLocal          = 0x02,
    VLCMediaFetchNetwork        = 0x04,
};
typedef int VLCMediaParsingOptions;

/**
 * triggers an asynchronous parse of the media item
 * using the given options
 * \param the option mask based on VLCMediaParsingOptions
 * \see VLCMediaParsingOptions
 * \return an int. 0 on success, -1 in case of error
 * \note listen to the "parsed" key value or the mediaDidFinishParsing:
 * delegate method to be notified about parsing results. Those triggers
 * will _NOT_ be raised if parsing fails and this method returns an error.
 */
- (int)parseWithOptions:(VLCMediaParsingOptions)options;

/**
 * Add options to the media, that will be used to determine how
 * VLCMediaPlayer will read the media. This allow to use VLC advanced
 * reading/streaming options in a per-media basis
 *
 * The options are detailed in vlc --long-help, for instance "--sout-all"
 * And on the web: http://wiki.videolan.org/VLC_command-line_help
*/
- (void) addOptions:(NSDictionary*) options;

/**
 * Getter for statistics information
 * Returns a NSDictionary with NSNumbers for values.
 *
 */
@property (NS_NONATOMIC_IOSONLY, readonly, copy) NSDictionary *stats;

#pragma mark - individual stats

/**
 * returns the number of bytes read by the current input module
 * \return a NSInteger with the raw number of bytes
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfReadBytesOnInput;
/**
 * returns the current input bitrate. may be 0 if the buffer is full
 * \return a float of the current input bitrate
 */
@property (NS_NONATOMIC_IOSONLY, readonly) float inputBitrate;

/**
 * returns the number of bytes read by the current demux module
 * \return a NSInteger with the raw number of bytes
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfReadBytesOnDemux;
/**
 * returns the current demux bitrate. may be 0 if the buffer is empty
 * \return a float of the current demux bitrate
 */
@property (NS_NONATOMIC_IOSONLY, readonly) float demuxBitrate;

/**
 * returns the total number of decoded video blocks in the current media session
 * \return a NSInteger with the total number of decoded blocks
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfDecodedVideoBlocks;
/**
 * returns the total number of decoded audio blocks in the current media session
 * \return a NSInteger with the total number of decoded blocks
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfDecodedAudioBlocks;

/**
 * returns the total number of displayed pictures during the current media session
 * \return a NSInteger with the total number of displayed pictures
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfDisplayedPictures;
/**
 * returns the total number of pictures lost during the current media session
 * \return a NSInteger with the total number of lost pictures
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfLostPictures;

/**
 * returns the total number of played audio buffers during the current media session
 * \return a NSInteger with the total number of played audio buffers
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfPlayedAudioBuffers;
/**
 * returns the total number of audio buffers lost during the current media session
 * \return a NSInteger with the total number of displayed pictures
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfLostAudioBuffers;

/**
 * returns the total number of packets sent during the current media session
 * \return a NSInteger with the total number of sent packets
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfSentPackets;
/**
 * returns the total number of raw bytes sent during the current media session
 * \return a NSInteger with the total number of sent bytes
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfSentBytes;
/**
 * returns the current bitrate of sent bytes
 * \return a float of the current bitrate of sent bits
 */
@property (NS_NONATOMIC_IOSONLY, readonly) float streamOutputBitrate;
/**
 * returns the total number of corrupted data packets during current sout session
 * \note value is 0 on non-stream-output operations
 * \return a NSInteger with the total number of corrupted data packets
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfCorruptedDataPackets;
/**
 * returns the total number of discontinuties during current sout session
 * \note value is 0 on non-stream-output operations
 * \return a NSInteger with the total number of discontinuties
 */
@property (NS_NONATOMIC_IOSONLY, readonly) NSInteger numberOfDiscontinuties;

@end
