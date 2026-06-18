// DebugMenu.h
//
// Lightweight, self-contained instrumentation for the GraphQL "schema paths"
// used by RedditFilter's NSURLSession hook.
//
// Reddit periodically renames pieces of its GraphQL schema (e.g. `homeV3` ->
// `homeV4`). When that happens the hardcoded key paths in Tweak.xm silently
// stop resolving and filtering breaks with no visible signal. This tracker:
//
//   * records, per operation, whether the hardcoded fast-path resolved (hit)
//     or returned nil (miss),
//   * on the first miss, walks the live response to auto-discover where the
//     data moved to, and
//   * surfaces all of that in a debug section of the RedditFilter menu so the
//     corrected path can be copied straight out of the app.
//
// EVERYTHING here is gated behind REDDITFILTER_DEBUG. Set it to 0 (or define it
// to 0 via the build) for a release build and the tracker, the recording call
// sites, and the debug menu all compile away to nothing.

#ifndef REDDITFILTER_DEBUG
// 1 on the test branch. Flip to 0 (or pass -DREDDITFILTER_DEBUG=0) for release.
#define REDDITFILTER_DEBUG 1
#endif

// Identifies the *shape* of the data that is expected at a given schema path so
// that, on a miss, discovery knows what it is looking for. These constants are
// always defined (they are cheap and only ever appear as dropped macro
// arguments in a release build), which keeps the call sites in Tweak.xm
// identical regardless of the flag.
typedef NS_ENUM(NSInteger, RFSchemaSig) {
  RFSchemaSigEdges = 0,   // an array of `{ node: {...} }` (home / popular feeds)
  RFSchemaSigTrees,       // an array of comment-forest trees: `{ node: {...} }`
  RFSchemaSigNodeArray,   // an array of post nodes, each with a `__typename`
  RFSchemaSigCommentsAds, // an array of comment ads (often empty)
};

#if REDDITFILTER_DEBUG

#import <Foundation/Foundation.h>

// Keys used in the dictionaries returned by -snapshot.
extern NSString *const kRFDebugOp;            // NSString  operation name
extern NSString *const kRFDebugExpected;      // NSString  hardcoded schema path
extern NSString *const kRFDebugHits;          // NSNumber  times the path resolved
extern NSString *const kRFDebugMisses;        // NSNumber  times the path was nil
extern NSString *const kRFDebugDiscovered;    // NSString  auto-found path (or absent)
extern NSString *const kRFDebugLastResolved;  // NSNumber  BOOL, last probe outcome
extern NSString *const kRFDebugSeen;          // NSNumber  BOOL, any traffic observed

@interface RFSchemaDebug : NSObject

+ (instancetype)shared;

// Called from the network hook for every probed operation. Thread-safe.
// `resolved` is the result of testing the hardcoded path against `json`.
// On the first miss for an operation, `json` and `signature` are used to try
// to locate where the data moved to.
- (void)recordOperation:(NSString *)operation
           expectedPath:(NSString *)expectedPath
               resolved:(BOOL)resolved
                   json:(id)json
              signature:(RFSchemaSig)signature;

// Ordered, immutable view of the current stats for the menu (seed order first,
// then any operations discovered at runtime). Thread-safe.
- (NSArray<NSDictionary *> *)snapshot;

// Zero all counters and clear discovered paths (re-arm the probes).
- (void)reset;

@end

// Recording macro used at the call sites. In a release build it expands to a
// no-op and, because none of its parameters appear in the replacement text,
// the arguments (including any block/enum tokens) are discarded entirely.
#define RF_RECORD_SCHEMA(op, expected, resolved, json, sig)                    \
  [[RFSchemaDebug shared] recordOperation:(op)                                 \
                             expectedPath:(expected)                           \
                                 resolved:(resolved)                           \
                                     json:(json)                               \
                                signature:(sig)]

#else // !REDDITFILTER_DEBUG

#define RF_RECORD_SCHEMA(op, expected, resolved, json, sig) ((void)0)

#endif // REDDITFILTER_DEBUG
