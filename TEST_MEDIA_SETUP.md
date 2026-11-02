# TEST_MEDIA_SETUP.md — How to Attach the User's Media

The **lightweight** specification ZIP contains the five photo fixtures but **not** the GoPro MP4 clips. The **full-media** ZIP contains **all three** MP4 videos already in the paths below. If using the lightweight ZIP, copy the videos there before video integration tests. This file is descriptive; an agent should not download from private links or guess paths.

```text
test_media/
  photos/
    IMG_3635.jpeg
    P7310233.JPG
    P8110319.JPG
    B663700C-50E6-4C26-B95F-25C7E5F271E9.JPG
    image.png
  videos/
    GX011123.MP4
    GX011176.MP4
    GX011247.MP4              # VERIFIED 10-bit HEVC Main 10 / Rec.709 SDR
```

The 10-bit file has already been verified: HEVC Main 10, 5312×2988, `yuv420p10le`, 29.97fps, Rec.709 SDR, −90° rotation, AAC stereo. Its duplicate upload (`GX011247(1).MP4`) is byte-for-byte identical and is not needed. The video originals are already included in the **full-media** ZIP; with the smaller archive, supply them locally.

If other 10-bit or HDR videos are added, inspect their exact codec/bit depth/primaries/transfer/orientation before describing them. An SDR 10-bit sample does **not** validate HDR support.
