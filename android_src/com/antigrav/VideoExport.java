package com.antigrav;

// Video-Export für AntiGrav 3D: nimmt einzelne Bilder (RGBA) aus Godot entgegen,
// kodiert sie mit dem Hardware-Encoder des Handys als H.264 in eine MP4-Datei,
// legt das Video in der Galerie ab (Filme/AntiGrav) und kann es zum Teilen anbieten.

import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.media.Image;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;

public class VideoExport extends GodotPlugin {
	private static final String TAG = "AntiGravVideo";
	private MediaCodec enc;
	private MediaMuxer mux;
	private int track = -1;
	private boolean muxStarted = false;
	private int w, h, fps;
	private long inFrames = 0;
	private File out;
	private String lastError = "";

	public VideoExport(Godot godot) {
		super(godot);
	}

	@Override
	public String getPluginName() {
		return "VideoExport";
	}

	@UsedByGodot
	public String error() {
		return lastError;
	}

	@UsedByGodot
	public boolean begin(int width, int height, int framesPerSecond, int bitrate) {
		try {
			release();
			w = width;
			h = height;
			fps = framesPerSecond;
			inFrames = 0;
			Activity a = getActivity();
			out = new File(a.getCacheDir(), "antigrav_replay.mp4");
			if (out.exists()) out.delete();
			MediaFormat f = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h);
			f.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible);
			f.setInteger(MediaFormat.KEY_BIT_RATE, bitrate);
			f.setInteger(MediaFormat.KEY_FRAME_RATE, fps);
			f.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
			enc = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC);
			enc.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
			enc.start();
			mux = new MediaMuxer(out.getPath(), MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
			track = -1;
			muxStarted = false;
			return true;
		} catch (Exception e) {
			lastError = "begin: " + e;
			Log.e(TAG, lastError);
			release();
			return false;
		}
	}

	// ein Bild: RGBA, Breite w, Höhe h, Zeile für Zeile
	@UsedByGodot
	public boolean addFrame(byte[] rgba) {
		if (enc == null) return false;
		try {
			int idx = -1;
			for (int tries = 0; tries < 200 && idx < 0; tries++) {
				idx = enc.dequeueInputBuffer(10000);
				if (idx < 0) drain(false);
			}
			if (idx < 0) {
				lastError = "no input buffer";
				return false;
			}
			Image img = enc.getInputImage(idx);
			fillYuv(img, rgba);
			long pts = inFrames * 1000000L / fps;
			enc.queueInputBuffer(idx, 0, w * h * 3 / 2, pts, 0);
			inFrames++;
			drain(false);
			return true;
		} catch (Exception e) {
			lastError = "addFrame: " + e;
			Log.e(TAG, lastError);
			return false;
		}
	}

	// RGBA → YUV 4:2:0 in die Ebenen des Encoders schreiben (berücksichtigt Zeilen- und Pixelabstand)
	private void fillYuv(Image img, byte[] rgba) {
		Image.Plane[] p = img.getPlanes();
		ByteBuffer yB = p[0].getBuffer(), uB = p[1].getBuffer(), vB = p[2].getBuffer();
		int yRow = p[0].getRowStride(), yPix = p[0].getPixelStride();
		int uRow = p[1].getRowStride(), uPix = p[1].getPixelStride();
		int vRow = p[2].getRowStride(), vPix = p[2].getPixelStride();
		for (int y = 0; y < h; y++) {
			int src = y * w * 4;
			int dst = y * yRow;
			for (int x = 0; x < w; x++) {
				int r = rgba[src] & 255, g = rgba[src + 1] & 255, b = rgba[src + 2] & 255;
				src += 4;
				int Y = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
				yB.put(dst + x * yPix, (byte) Y);
			}
		}
		for (int y = 0; y < h / 2; y++) {
			for (int x = 0; x < w / 2; x++) {
				int s = ((y * 2) * w + x * 2) * 4;
				int r = rgba[s] & 255, g = rgba[s + 1] & 255, b = rgba[s + 2] & 255;
				int U = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
				int V = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
				uB.put(y * uRow + x * uPix, (byte) U);
				vB.put(y * vRow + x * vPix, (byte) V);
			}
		}
	}

	private void drain(boolean end) {
		MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
		while (true) {
			int o = enc.dequeueOutputBuffer(info, end ? 10000 : 0);
			if (o == MediaCodec.INFO_TRY_AGAIN_LATER) {
				if (!end) return;
				continue;
			} else if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
				track = mux.addTrack(enc.getOutputFormat());
				mux.start();
				muxStarted = true;
			} else if (o >= 0) {
				ByteBuffer data = enc.getOutputBuffer(o);
				if ((info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) info.size = 0;
				if (info.size > 0 && muxStarted && data != null) {
					data.position(info.offset);
					data.limit(info.offset + info.size);
					mux.writeSampleData(track, data, info);
				}
				enc.releaseOutputBuffer(o, false);
				if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return;
			}
		}
	}

	// Video abschließen und in die Galerie legen; liefert die Adresse (content://…) oder "" bei Fehler
	@UsedByGodot
	public String finish() {
		if (enc == null) return "";
		try {
			int idx = enc.dequeueInputBuffer(100000);
			if (idx >= 0) enc.queueInputBuffer(idx, 0, 0, inFrames * 1000000L / fps, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
			drain(true);
		} catch (Exception e) {
			lastError = "finish: " + e;
			Log.e(TAG, lastError);
		}
		release();
		try {
			return saveToGallery();
		} catch (Exception e) {
			lastError = "save: " + e;
			Log.e(TAG, lastError);
			return "";
		}
	}

	private String saveToGallery() throws Exception {
		Activity a = getActivity();
		ContentResolver cr = a.getContentResolver();
		String name = "AntiGrav_" + System.currentTimeMillis() + ".mp4";
		ContentValues cv = new ContentValues();
		cv.put(MediaStore.Video.Media.DISPLAY_NAME, name);
		cv.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
		if (Build.VERSION.SDK_INT >= 29) {
			cv.put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/AntiGrav");
			cv.put(MediaStore.Video.Media.IS_PENDING, 1);
		}
		Uri uri = cr.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, cv);
		if (uri == null) throw new Exception("MediaStore insert failed");
		try (OutputStream os = cr.openOutputStream(uri); InputStream is = new FileInputStream(out)) {
			byte[] buf = new byte[1 << 16];
			int n;
			while ((n = is.read(buf)) > 0) os.write(buf, 0, n);
		}
		if (Build.VERSION.SDK_INT >= 29) {
			ContentValues done = new ContentValues();
			done.put(MediaStore.Video.Media.IS_PENDING, 0);
			cr.update(uri, done, null, null);
		}
		return uri.toString();
	}

	// Standbild (PNG) in die Galerie legen: Bilder/AntiGrav
	@UsedByGodot
	public String savePng(byte[] png) {
		try {
			Activity a = getActivity();
			ContentResolver cr = a.getContentResolver();
			ContentValues cv = new ContentValues();
			cv.put(MediaStore.Images.Media.DISPLAY_NAME, "AntiGrav_" + System.currentTimeMillis() + ".png");
			cv.put(MediaStore.Images.Media.MIME_TYPE, "image/png");
			if (Build.VERSION.SDK_INT >= 29) {
				cv.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/AntiGrav");
				cv.put(MediaStore.Images.Media.IS_PENDING, 1);
			}
			Uri uri = cr.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cv);
			if (uri == null) throw new Exception("MediaStore insert failed");
			try (OutputStream os = cr.openOutputStream(uri)) {
				os.write(png);
			}
			if (Build.VERSION.SDK_INT >= 29) {
				ContentValues done = new ContentValues();
				done.put(MediaStore.Images.Media.IS_PENDING, 0);
				cr.update(uri, done, null, null);
			}
			return uri.toString();
		} catch (Exception e) {
			lastError = "savePng: " + e;
			Log.e(TAG, lastError);
			return "";
		}
	}

	// Teilen-Menü von Android öffnen (WhatsApp, Mail, …)
	@UsedByGodot
	public void share(String uriStr) {
		final Activity a = getActivity();
		if (a == null || uriStr == null || uriStr.isEmpty()) return;
		a.runOnUiThread(() -> {
			try {
				Intent i = new Intent(Intent.ACTION_SEND);
				i.setType("video/mp4");
				i.putExtra(Intent.EXTRA_STREAM, Uri.parse(uriStr));
				i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
				a.startActivity(Intent.createChooser(i, "AntiGrav Replay"));
			} catch (Exception e) {
				lastError = "share: " + e;
				Log.e(TAG, lastError);
			}
		});
	}

	private void release() {
		try {
			if (enc != null) {
				enc.stop();
				enc.release();
			}
		} catch (Exception ignored) {
		}
		enc = null;
		try {
			if (mux != null) {
				if (muxStarted) mux.stop();
				mux.release();
			}
		} catch (Exception ignored) {
		}
		mux = null;
		muxStarted = false;
	}
}
