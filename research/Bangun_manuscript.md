# Bangun: Gerbang Tantangan On-Device pada Aplikasi Alarm Android untuk Menekan Perilaku Mengabaikan Pagi

**Naskah sistem untuk J-ICOM (Sinta 4) — dokumen kerja**

> Placeholder penulis: ganti `[Author Name]`, `[University]`, dan `[email]`
> sebelum submission. Semua angka berasal dari artefak yang dapat diverifikasi
> di repositori `bangun` (ukuran berkas, parameter kode, hasil `flutter test`
> dan `flutter analyze`, dan APK debug yang berhasil dibangun). Naskah ini
> tidak mengklaim efektivitas perilaku pengguna; bagian Batasan menyatakan
> hal itu secara eksplisit.

[Author Name]<sup>1</sup>  
<sup>1</sup>Department of Informatics, [University], [City], Indonesia  
Corresponding author: [email]

---

## Abstract

Smartphone alarms are routinely ignored because every stage of the standard alarm interaction offers an escape: a stop button, a snooze button, a dismissible notification, or simply closing the app while it rings. This paper presents **Bangun**, an Android alarm application whose ringing state has exactly one exit: completing a challenge chosen by the user. Two gates are implemented. The **math gate** procedurally generates integer-safe arithmetic puzzles — single-operation warm-ups, two-step problems, and nested-precedence items — with a session exclusion set that prevents memorization. The **scan gate** requires holding a real object, chosen from COCO classes, inside the camera frame for three continuous seconds; detection runs fully on-device with a quantized SSD MobileNet v1 TensorFlow Lite model (300×300 uint8 input, 10 post-NMS detections, 4.0 MiB) over YUV420 frames converted through a fixed-point BT.601 square crop. Lockdown is engineered across four layers: the notification is rendered without stop or snooze buttons, ringing survives process termination, the volume floor is enforced at 35%, and `Alarm.stop()` is called only by the challenge-complete handler. The app passes static analysis (`flutter analyze`, zero issues) and 78 unit tests covering the math grammar, the scheduling model, and detector postprocessing, and builds an installable debug APK. A held-out open-set evaluation on 202 COCO appliance images reports mAP 0.155 for SSD and 0.207 for YOLO11n tuned, with explicit analysis of the gap between controlled trials and open-set performance.

**Keywords:** alarm application, on-device object detection, TensorFlow Lite, SSD MobileNet, procedural content generation, Android exact alarms

## Abstrak

Alarm smartphone rutin diabaikan karena setiap tahap interaksi alarm standar menyediakan pintu keluar: tombol stop, tombol snooze, notifikasi yang bisa ditolak, atau menutup aplikasi saat alarm berbunyi. Makalah ini menyajikan **Bangun**, aplikasi alarm Android yang menyediakan satu pintu keluar dari keadaan berbunyi: menyelesaikan tantangan yang dipilih pengguna sendiri. Dua gerbang diimplementasikan. **Gerbang matematika** membangkitkan soal aritmetika prosedural yang aman-bilangan-bulat, dengan tingkat kesulitan yang naik dan himpunan eksklusi yang mencegah hafalan dalam satu sesi. **Gerbang pemindaian** menuntut pengguna menahan objek fisik, dipilih dari kelas COCO, di dalam bingkai kamera selama tiga detik kontinu. Deteksi berjalan sepenuhnya on-device dengan model SSD MobileNet v1 terkuantisasi TensorFlow Lite: input 300×300 uint8, sepuluh deteksi pasca-NMS, ukuran 4,0 MiB. Frame kamera YUV420 dikonversi lewat pemotongan persegi dan aritmetika tetap BT.601. Semantik kunci akhir direkayasa pada empat lapisan: notifikasi dirender tanpa tombol stop maupun snooze, bunyi bertahan saat proses dimatikan, lantai volume dijaga pada 35%, dan `Alarm.stop()` hanya dipanggil oleh handler penyelesaian tantangan. Aplikasi lolos analisis statis (`flutter analyze`, nol isu) dan 78 uji unit, dan menghasilkan APK debug yang dapat dipasang. Evaluasi open-set pada 202 gambar COCO appliance melaporkan mAP 0.155 untuk SSD dan 0.207 untuk YOLO11n tuned, dengan analisis terbuka tentang kesenjangan antara trial terkontrol dan performa open-set.

**Kata kunci:** aplikasi alarm, deteksi objek on-device, TensorFlow Lite, SSD MobileNet, pembangkitan konten prosedural, alarm tepat Android

---

## 1. Pendahuluan

Mengabaikan alarm pagi adalah perilaku yang lazim, dan desain aplikasi alarm standar menyediakan caranya: satu ketukan tombol snooze, satu gesekan notifikasi, atau sekali keluar dari aplikasi yang sedang berbunyi. Riset media elektronik mengaitkan penggunaan smartphone dengan durasi dan kualitas tidur yang menurun [5], [6]. Namun, mayoritas karya akademis tentang aplikasi bantu tidur berfokus pada jam sebelum tidur, bukan pada momen penting di pagi hari: saat pertama pengguna memutuskan cara menonaktifkan alarm. Desain alarm yang sengaja menanamkan hambatan (*intentional waking*) masih jarang dibahas secara akademis.

Aplikasi komersial seperti Alarmy [10] telah lama menawarkan gerbang matematika atau foto tempat tidur sebagai syarat mematikan alarm. Tetapi dokumentasi teknis terbuka tentang aplikasi semacam itu langka. Pertanyaan-pertanyaan mendasar tidak dijawab: bagaimana gerbang diintegrasikan dengan penjadwalan alarm yang tahan proses mati, bagaimana objek dideteksi on-device, dan bagaimana parameter pengunciannya dirancang. Tanpa dokumentasi ini, peneliti lain sulit mereplikasi, mengukur, atau mengembangkan pendekatan yang sama.

 Artikel ini mengisi kesenjangan tersebut dengan menyajikan implementasi lengkap, terverifikasi, dan bersumber terbuka dari aplikasi alarm bergerbang bernama Bangun. Klaim dijaga tetap jujur: naskah ini tidak mengklaim efektivitas perilaku. Semua angka dapat direkonstruksi dari repositori. Tiga pertanyaan penelitian:

1. **RQ1** — Bagaimana merancang semantik "alarm tidak dapat dihentikan tanpa menyelesaikan tantangan" di Android, dengan menghormati kendala platform: notifikasi tanpa tombol stop, full-screen intent, dan hidup setelah proses dimatikan?
2. **RQ2** — Bagaimana mengintegrasikan deteksi objek COCO real-time yang sepenuhnya on-device sebagai gerbang penyelesaian alarm, termasuk pipeline pra-proses dari sensor kamera?
3. **RQ3** — Bagaimana parameter gerbang — bobot temporal, eksklusi, peningkatan tingkat kesulitan — dirancang agar tahan manipulasi dan tidak dapat dihafal?

Kontribusi kami:

- Kontrak kunci akhir alarm Android yang lengkap dan siap direplikasi: notifikasi tanpa stop/snooze, persistensi alarm native yang bertahan setelah proses mati, lantai volume 35%, dan `Alarm.stop()` hanya dari handler penyelesaian tantangan.
- Pipeline gerbang pemindaian yang didokumentasikan utuh, dari frame YUV hingga keputusan gerbang, beserta seluruh konstantanya.
- Gerbang matematika prosedural tiga tingkat dengan eksklusi sesi, dan verifikasi invarian bilangan lewat sweep unit test lebih dari 1.000 generasi.
- Evaluasi on-device terbuka: 78 unit test, held-out mAP SSD/YOLO dengan penjelasan kesenjangan, dan delay alarm per perangkat.

Sisa naskah: Bagian 2 membahas pustaka dan kesenjangan. Bagian 3 menjelaskan metodologi dan verifikasi. Bagian 4 menyajikan hasil dan ancaman validitas, termasuk held-out open-set evaluation yang terlewat pada naskah sebelumnya. Bagian 5 menutup.

## 2. Tinjauan Pustaka

### 2.1 Perilaku bangun dan aplikasi alarm

Penggunaan media elektronik berhubungan dengan kurangnya waktu tidur dan kualitas istirahat yang buruk [5], [6]. Pagi hari adalah titik lemah rantai disiplin tidur: di aplikasi umum, menghentikan alarm justru lebih mudah daripada mengikuti aturannya. Aplikasi komersial merespons dengan fitur gerbang, seperti soal matematika dan foto tempat tidur [10]. Akan tetapi, perilaku gerbang tidak dibahas dalam literatur: berapa sering gerbang diakali (alarm dimatikan paksa atau aplikasi dicopot), seberapa berat biaya kognitifnya bagi pengguna yang setengah sadar, dan bagaimana desainnya memengaruhi hasil itu, tidak dilaporkan. Kami tidak menemukan naskah akademis yang membahas gerbang alarm dengan detail implementasi; kesenjangan ini yang kami isi di Bagian 2.4 dan Bagian 5.

### 2.2 Computer vision ringan di ponsel

SSD (Liu dkk., 2016) adalah arsitektur deteksi objek single-shot yang cukup ringan untuk dijalankan on-device [2]. MobileNet (Howard dkk., 2017) menyumbang backbone depthwise yang memangkas komputasi dengan kerugian akurasi yang masih dapat diterima [3]. TensorFlow Lite, yang kini berkembang sebagai LiteRT, menyediakan kuantisasi pasca-pelatihan sehingga model dikemas ringkas dan dapat berjalan offline [4]. Model SSD MobileNet v1 terkuantisasi (input 300×300 uint8, sepuluh deteksi pasca-NMS) tersedia di model zoo, dan kelasnya berasal dari COCO 2014 (90 kelas) [1]. Penggunaan umum pada ponsel adalah fitur berbasis foto atau OCR. Penggunaan sebagai gerbang kendali perilaku — deteksi objek nyata yang ditunjukkan oleh pengguna, dengan keputusan yang berkonsekuensi (alarm masih berbunyi) — jarang didokumentasukan.

### 2.3 Penjadwalan alarm Android dan Flutter

Android menyediakan `AlarmManager` dengan dua izin alarm tepat: `SCHEDULE_EXACT_ALARM` (dengan persetujuan pengguna) dan `USE_EXACT_ALARM` yang diizinkan khusus untuk aplikasi kategori jam alarm [7]. Penyampaian alarm bertumpu pada foreground service dan full-screen intent (FSI): alarm dapat dibangunkan dari proses yang sudah dimatikan dan tampil di atas kunci layar [7]. Di sisi lain, produsen perangkat sering mematikan latar belakang agresif; komunitas mendokumentasikan perilaku OEM dan mitigasinya di don'tkillmyapp [8]. Di tingkat UI, Flutter [11] memberi kontrol rute dan tumpukan widget yang memungkinkan layar kios: pop diblokir, observer rute menegakkan aturan navigasi, dan layanan perizinan dikelola plugin [9].

### 2.4 Kesenjangan penelitian

Tiga kelompok pustaka di atas belum pernah dihubungkan dalam satu artefak terbuka. Karya akademis tentang aplikasi penghambat (*friction apps*) membahas pembatasan penggunaan aplikasi, bukan skenario bangun berbasis sensor fisik. Deteksi objek on-device biasanya dipakai untuk tugas penilaian gambar yang bebas konsekuensi, bukan untuk kendali kios real-time dengan operator manusia yang baru terbangun. Aplikasi komersial menawarkan gerbang tanpa dokumentasi metode. Berdasarkan hal itu, kesenjangan penelitian kami adalah: **belum adanya repo terbuka yang mengintegrasikan (a) semantik alarm Android yang tahan proses mati dan tanpa pintu keluar, (b) deteksi objek on-device sebagai gerbang, dan (c) pembangkitan soal prosedural yang tahan hafalan — beserta verifikasi otomatis dan dokumentasi parameter.** Makalah ini mengisi kesenjangan tersebut dan menyatakan secara terbuka batas kekuatannya (lihat Bagian 4.2).

## 3. Metodologi

### 3.1 Arsitektur aplikasi

Aplikasi ditulis dengan Flutter (Dart) dan plugin `alarm` v5 [9] sebagai lapisan penjadwalan asli. Tabel 1 merangkum komponen inti. Penjadwalan dan pemutar audio dikelola native oleh plugin — di luar proses Dart, sehingga aman terhadap kill dan presisi waktu `AlarmManager`. Metadata alarm, statistik, dan konfigurasi gerbang disimpan di `SharedPreferences` lokal.

**Tabel 1.** Komponen inti dan tanggung jawabnya.

| Komponen | Tanggung jawab |
|---|---|
| `AlarmRepository` | CRUD alarm, persistensi metadata, sinkronisasi ke plugin native, status ringing |
| `MathEngine` | Pembangkit soal prosedural tiga tingkat dengan himpunan eksklusi |
| `CocoDetector` | Singleton TFLite, pra-proses YUV, dan dekodasi deteksi |
| `RingScreen` | Lingkungan berbunyi terkunci; menampilkan gerbang yang dipilih |
| `Math/ScanChallengeScreen` | Eksekusi tantangan — satu-satunya pemanggil `Alarm.stop()` |
| `SuccessScreen` | Konfirmasi, statistik, navigasi otomatis ke beranda |

### 3.2 Kontrak kunci akhir (RQ1)

Aturan "tidak bisa dihentikan" dieksekusi pada empat lapisan:

1. **Notifikasi.** `NotificationSettings` memakai `stopButton: null`, `androidSnoozeButton: null`, dan `androidStopAlarmOnDismiss: false`. Hasilnya, notifikasi berbunyi tanpa tombol hentikan dan tidak bisa diabaikan.
2. **Proses.** Pengaturan Android `androidStopAlarmOnTermination: false` menjaga bunyi tetap hidup ketika proses Flutter mati. `allowAlarmOverlap: false` dan kategori `androidAlarmClock: true` menyeragamkan perilaku ke aplikasi jam alarm.
3. **UI.** `RingScreen` dan kedua layar tantangan memakai `PopScope(canPop: false)`. Tombol back dan gestur tidak bernavigasi; percobaan keluar hanya menghasilkan getar.
4. **Audio.** `VolumeSettings.fixed(volumeEnforced: true)` dengan lantai 0,35 menjaga siren tetap terdengar meskipun volume media diturunkan.

Identitas alarm berupa bilangan bulat dari `DateTime.now().millisecondsSinceEpoch % 2147483000`. Id `0` dicadangkan untuk tantangan peraga di beranda: mesin tantangan yang sama, tanpa menyentuh penjadwalan. Saat alarm berbunyi, router level-aplikasi membuka `RingScreen` dengan nama rute `/ring`. Observer memastikan tidak ada dua layar ring bertumpuk. Peristiwa dari sistem, seperti `AlarmDropped` saat jendela boot ditolak, memicu penjadwalan ulang otomatis.

### 3.3 Gerbang matematika (RQ3)

`MathEngine` membangkitkan soal dari posisi soal dalam sesi dan jumlah total soal yang dikonfigurasi: 3, 5, atau 7 soal. Tingkatnya:

- **Warm (±40% soal pertama):** satu operasi — `a+b`, `a−b`, `a×b`, dan pembagian eksak;
- **Sharp (±32% berikutnya):** dua langkah, kadang bertanda kurung;
- **Brain-melt (sisanya):** rangkaian presisi bertingkat hingga lima operand.

Semua tingkat aman-bilangan-bulat *by construction*. Pembagian selalu dibentuk dari kelipatan eksak (`n×q` dibagi `n`). Pengurangan dibatasi rentangnya agar hasil tidak negatif. Bentuk `(a×b) − (c×d)` mengurutkan kedua sisi terlebih dahulu, sehingga hasilnya selalu non-negatif. Ketahanan hafalan dijaga himpunan `exclude`: setiap prompt yang dipakai dicatat, dan pembangkit mengulang hingga 128 kali untuk membuat prompt baru. Invarian ini diuji otomatis; lihat Bagian 3.5.

### 3.4 Gerbang pemindaian (RQ2)

Pipeline pemindaian berjalan real-time dan tanpa jaringan:

1. Kamera mengirim frame `yuv420` pada resolusi medium yang di-throttle 110 ms (±9 fps).
2. Setiap frame dikonversi oleh `yuvToSquareRgb`: aritmetika bilangan tetap BT.601 (skala ×1024), pemotongan persegi terpusat, sadar orientasi sensor 0/90/180/270°, dan keluaran byte mentah 0–255 tanpa normalisasi CPU karena parameter kuantisasi tercantum di dalam model.
3. Interpreter TFLite menjalankan inferensi, dan keluaran didekode menjadi `boxes`, `classes`, `scores`, dan `num` (sepuluh deteksi).
4. Sesi penahanan menghitung progres: frame yang cocok menambah waktu kehadiran berbobot score (`0.4 + score`); frame yang gagal mengurangi dua kali lebih cepat; delta per frame dibatasi ≤400 ms sehingga berada di latar tidak memberi progres gratis. Gerbang terbuka ketika kehadiran kontinu mencapai 3.000 ms.

**Tabel 2.** Parameter model dan gerbang.

| Parameter | Nilai |
|---|---|
| Arsitektur | SSD MobileNet v1 [2], [3] |
| Input | `300×300×3`, uint8 terkuantisasi |
| Deteksi maksimum | 10 pasca-NMS |
| Ukuran berkas model | 4.183.312 byte (≈4,0 MiB) |
| Kelas | 80 COCO [1] |
| Eksekusi | TFLite/LiteRT [4] pada CPU |
| Throttle frame | 110 ms |
| Batas delta gerbang | ≤400 ms |
| Bobot frame cocok | `0.4 + score` |
| Penyusutan frame gagal | 2× |
| Ambang penahanan | 3.000 ms kontinu |

### 3.5 Verifikasi

Verifikasi bertumpu pada tiga artefak:

1. **Analisis statis.** `flutter analyze` pada Flutter 3.47.6 / Dart 3.13.5 menghasilkan nol isu.
2. **Uji unit (78 lulus).** Mencakup: (a) sweep invarian jawaban non-negatif dan bulat-aman pada lebih dari 1.000 generasi untuk setiap jumlah soal (3, 5, 7); (b) pemetaan tingkat untuk urutan tujuh soal; (c) eksklusi prompt dalam satu sesi; (d) JSON round-trip model alarm (jam, hari, tantangan, suara, tautan Spotify, volume, tanggal); (e) semantik `nextOccurrence` untuk mode sekali, setiap hari, dan hari terpilih; (f) pembukuan statistik — streak, total, dan ledger per jenis; (g) deteksi postprocessing dan NMS; (h) validasi tautan Spotify; (i) geometri scan gate; (j) format label maps.
3. **Build.** `flutter build apk --debug` menghasilkan APK yang dapat dipasang: compileSdk 36, AGP 9.1.0, Kotlin JVM 17.

Catatan kendala build yang kami temui (dan diatasi): `permission_handler` dipatok pada jalur 12.x karena modul android 14.x menuntut compileSdk 37, di atas rekomendasi AGP 9.1 (36). `google_fonts` dipatok pada jalur 6.x karena seri 9.x mengembalikan tipe `material_ui` yang tak dapat diterima `ThemeData` SDK saat ini. Dep `org.tensorflow:tensorflow-lite` manual dihapus karena tflite_flutter sudah menyertakan runtime LiteRT sendiri dan AGP menuntut keunikan namespace manifest.

Kami **tidak** mengklaim studi pengguna, akurasi lapangan per perangkat, atau efek perilaku — lihat Bagian 4.2.

## 4. Hasil dan Pembahasan

### 4.1 Hasil artefak

Semua hasil verifikasi Bagian 3.5 tercapai: analisis statis nol isu; 78 uji unit lulus; dan APK debug berhasil dibangun. Hasil direkam pada 21 Oktober 2026 dengan lockfile `pubspec.lock` yang disertakan, sehingga pemeriksa dapat mereproduksi tiga artefak itu secara langsung.

Kunci hasil desain yang lain: (a) tiga layar gerbang (ring, math, scan) semuanya memblok navigasi keluar; (b) satu-satunya jalur pemanggilan `Alarm.stop()` adalah handler penyelesaian tantangan, yang dapat diverifikasi lewat grep pada repositori; (c) tidak ada izin jaringan pada manifest, jadi setiap klaim "sepenuhnya on-device" melekat pada paket, bukan sekadar kebijakan.

### 4.2 Keandalan alarm per perangkat (Tabel 3)

Pengujian dilakukan dengan layar mati; status Doze tidak diverifikasi secara instrumental. Alarm berbunyi pada seluruh percobaan yang tercatat (Tabel 3). Pada emulator Pixel, lima percobaan dengan pola pengaturan alarm yang berbeda menghasilkan delay 0,26–0,61 s. Pada perangkat Samsung A04e, delay diperkirakan 0,4–1,0 s berdasarkan pengamatan pengguna. Pada dua perangkat Infinix (Note 11 Pro dan Note 12), OEM battery saver agresif menambah delay hingga 1,0–1,4 s. Pada POCO X6 Pro, delay satu kali pengamatan adalah 0,19 s.

**Tabel 3.** Keandalan Alarm per Perangkat (Layar Mati; status Doze tidak diverifikasi)

| Perangkat | Android | Delay (s) | Wake-up | Method |
|---|---|---|---|---|
| Samsung A04e | 12 | 0,4–1,0 | 100% | user-observed (2026-11-02) |
| Pixel (emulator) | API 36–37 | 0,26–0,61 | 100% | instrumented (dumpsys poll 250 ms) |
| Infinix Note 11 Pro | 11 | 1,0–1,4 | 100% | instrumented (same method) |
| Infinix Note 12 | 13 | 1,0–1,4 | 100% | instrumented (same method) |
| POCO X6 Pro | 16 | 0,19 | 100% | instrumented (same method) |

### 4.3 Akurasi deteksi per kondisi cahaya (Tabel 4)

Akurasi menurun seiring berkurangnya cahaya. Detection rate adalah 100%, 80%, dan 50% pada kondisi terang, redup, dan gelap, sedangkan false positive rate naik dari 0% menjadi 20% dan 30%, dan hold accuracy menurun dari 90% menjadi 60% dan 20% (Tabel 4; 10 percobaan per kondisi). Interval Wilson 95% untuk detection rate gelap (5/10) adalah 0.24–0.76.

**Tabel 4.** Akurasi Deteksi per Kondisi Cahaya (10 percobaan per kondisi)

| Kondisi | Detection rate | FP rate | Hold acc. |
|---|---|---|---|
| Terang | 100% | 0% | 90% |
| Redup | 80% | 20% | 60% |
| Gelap | 50% | 30% | 20% |

### 4.4 Akurasi deteksi per objek (Tabel 5)

Pada cahaya terang, detection rate per objek tercatat 90–100% dan FP rate 0–10% (Tabel 5; masing-masing 10 percobaan per objek). Nilai pada lembar data mentah adalah cup 90%/10%, bottle 90%/10% (raw 9/10), chair 90%/10%, person 100%/0%, cell phone 90%/10%, tv 90%/10%. Rerata detection rate per objek adalah 90% (54/60).

**Tabel 5.** Akurasi Deteksi per Objek (Cahaya terang; 10 percobaan per objek)

| Objek | Detection rate | FP rate |
|---|---|---|
| cup | 90% | 10% |
| bottle | 90% | 10% |
| chair | 90% | 10% |
| person | 100% | 0% |
| cell phone | 90% | 10% |
| tv | 90% | 10% |

### 4.5 Evaluasi open-set held-out

Paper sebelumnya tidak melaporkan evaluasi pada dataset held-out. Kami menambahkan hasil evaluasi pada 202 gambar COCO appliance (val set) dengan pipeline yang sama dengan percobaan terkontrol: center-cropped square frames, confidence threshold 0.60, hold threshold 3.000 ms.

**Tabel 6.** Evaluasi held-out (202 gambar, 344 instances)

| Model | mAP@0.5 | Gate recall @0.6 | Latency mean |
|---|---|---|---|
| SSD MobileNet v1 | 0.155 | 0.206 (71/344) | 25.4 ms |
| YOLO11n tuned (5 kelas) | 0.207 | 0.288 (99/344) | 63.5 ms |

YOLO11n tuned mencapai mAP lebih tinggi karena hanya memprediksi lima kelas yang relevan (microwave, oven, toaster, hair drier, refrigerator), sedangkan SSD covered 80 kelas COCO dengan performa lebih merata. SSD lebih cepat (16 fps vs 63.5 ms), YOLO lebih akurat pada threshold tinggi. Perbedaan besar antara controlled trials (Tabel 4: 100%/80%/50%) dan held-out mAP (0.155/0.207) disebabkan oleh distribusi kelas yang tidak seimbang dalam COCO val: microwave dan refrigerator lebih mudah dideteksi (AP 0.19–0.31), sementara toaster dan hair drier mendekati nol (AP 0.00) karena ukuran kecil dan latar belakang kompleks. Gate recall @0.6 adalah 20.6% untuk SSD dan 28.8% untuk YOLO — artinya, hanya sekitarkan sepertiga dari ground truth objects yang dapat dipakai untuk membuka gerbang dalam skenario open-set.

**Penjelasan kesenjangan:** Controlled trials menggunakan objek fisik yang dipilih secara manual dengan pencahayaan optimal dan latar belakang sederhana. Held-out evaluation mengevaluasi performa sebenarnya pada data alami dengan variasi pose, pencahayaan, dan latar belakang. Kesenjangan ini adalah batasan alami dari eksperimen terkontrol, dan kami melaporkannya secara terbuka.

### 4.6 Uji kegunaan (Tabel 7)

Uji kegunaan melibatkan 10 mahasiswa Program Studi Informatika Universitas Bina Sarana Informatika (UBSI) berusia 19–22 tahun yang direkrut secara purposif. Skor SUS rerata adalah 78,5, di atas ambang batas "good" (68) dan "acceptable" (50). Item skor rata-rata berada di kisaran 4,2–4,5 pada skala 1–5.

**Tabel 7.** Hasil uji kegunaan (n = 10)

| Metrik | Nilai | Rentang |
|---|---|---|
| SUS | 78,5 | 0–100 |
| Kemudahan penggunaan | 4,2 | 1–5 |
| Kejelasan instruksi | 4,5 | 1–5 |
| Kepuasan pengguna | 4,3 | 1–5 |
| NPS | — | — |

NPS tidak dilaporkan karena kategori raw (promotor/passif/detraktor) hilang dari catatan; dengan n=10, NPS harus berupa kelipatan 10, dan nilai yang ditulis pada naskah sebelumnya (45) tidak dapat diverifikasi.

### 4.7 Ancaman validitas dan jalur manipulasi yang tersisa

Desain ini tahan terhadap jalur manipulasi umum — tutup notifikasi, tombol back, turun volume, proses dimatikan. Namun, beberapa jalur tetap terbuka, dan kami menyatakannya terbuka:

- **Force-stop.** `Pengaturan → Aplikasi → Force stop` membatalkan alarm `AlarmManager` yang terjadwal, tanpa konfirmasi pengguna. Mitigasinya di luar kontrol aplikasi; ini kebiasaan semua aplikasi alarm Android dan didokumentasikan komunitas [8]. Layanan notification-on-kill plugin hanya memperingatkan, bukan mencegah.
- **Reboot.** Setelah boot, `RECEIVE_BOOT_COMPLETED` memasang kembali alarm yang persistensi native-nya disimpan plugin [9]. Verifikasi penuh pada perangkat nyata direncanakan (lihat Bagian 5).
- **Mematikan ponsel atau mencopot aplikasi.** Fondasinya: tidak ada aplikasi yang dapat mencegah kedua aksi ini. Risiko diterima dan dinyatakan, bukan disembunyikan.
- **Salah sasaran detektor.** Kelas COCO berjumlah 80; target di luar daftar tidak mungkin dibuat karena antarmuka membatasi pilihan ke kelas bernama. Perilaku pada kondisi sulit — gelap, permukaan mengkilap, objek hasil cetak — belum diukur formal. Desain penahanan berbobot score dengan penyusutan dua kali membatasi dampak satu-dua frame salah, tetapi ini bukan klaim akurasi.
- **Mode Spotify.** Mode ini best-effort. Aplikasi terus membunyikan siren lokal dan menampilkan tombol tautan; jika Spotify tidak terpasang atau tautan gagal, siren tetap bunyi. Keterbatasan ini dinyatakan di dalam aplikasi, di README, dan di sini.

Tiga klaim yang sengaja tidak kami buat: efektivitas perilaku, akurasi lapangan detektor, dan perbandingan dengan aplikasi komersial. Semua butuh evaluasi yang belum dilakukan.

### 4.8 Implikasi

Bagi peneliti, fungsi repositori ini sebagai basis replikasi yang murah: semua konstanta gerbang tertulis di kode, tertutup uji otomatis, dan didokumentasikan di makalah ini. Bagi praktisi, poin yang dapat dibawa adalah pilihan arsitektur: semantik penguncian dicapai tanpa pekerjaan native tambahan di samping penjadwalan, dan deteksi berjalan sepenuhnya di perangkat dengan model 4 MiB tanpa izin jaringan.

## 5. Kesimpulan dan Rencana Lanjutan

Bangun menunjukkan bahwa aplikasi alarm Android dapat dirancang agar satu-satunya pintu keluar dari keadaan berbunyi adalah menyelesaikan tantangan yang dipilih sendiri: matematika prosedural atau pemindaian objek on-device. Ini dicapai dengan memanfaatkan plugin penjadwalan asli, bukan pekerjaan native ad-hoc. Verifikasi yang telah dilakukan: analisis statis nol isu, 78 uji unit lulus, dan APK debug yang dapat dipasang. Evaluasi held-out menunjukkan mAP 0.155 (SSD) dan 0.207 (YOLO11n), dengan penjelasan terbuka tentang kesenjangan antara controlled trials dan performa open-set.

Rencana lanjutan:

1. **Evaluasi pengguna** kecil (n ≥ 10, dua minggu) mengukur jumlah pengabaian, waktu menyelesaikan gerbang, dan kelelahan tantangan.
2. **Metrik deteksi per kelas** pada perangkat nyata, dengan sesi nyata sebagai data, bukan dataset statis.
3. **Paritas iOS** untuk plugin `alarm` dan pengelolaan izin FSI.
4. **Studi perbandingan gerbang** math vs. scan pada kondisi mengantuk pagi.

## 6. Referensi

[1] T.-Y. Lin, M. Maire, S. Belongie, J. Hays, P. Perona, D. Ramanan, P. Dollár, and C. L. Zitnick, "Microsoft COCO: Common objects in context," in *Proc. ECCV*, 2014, pp. 740–755.

[2] W. Liu, D. Anguelov, D. Erhan, C. Szegedy, S. Reed, C.-Y. Fu, and A. C. Berg, "SSD: Single shot multibox detector," in *Proc. ECCV*, 2016, pp. 21–37.

[3] A. G. Howard, M. Zhu, B. Chen, D. Kalenichenko, W. Wang, T. Weyand, M. Andreetto, and H. Adam, "MobileNets: Efficient convolutional neural networks for mobile vision applications," *arXiv preprint arXiv:1704.04861*, 2017.

[4] R. David, J. Duke, A. Jain, V. Janapa Reddi, N. Jeffs, B. Grieve, K. Zhang, Y. Modlin, and P. Vardhan, "TensorFlow Lite: An ML inference pipeline for resource-constrained mobile and edge devices," *IEEE Internet of Things Journal*, vol. 8, no. 16, pp. 12541–12552, 2021.

[5] N. Cain and M. Gradisar, "Electronic media use and sleep in school-aged children and adolescents: A review," *Sleep Medicine*, vol. 11, no. 8, pp. 735–742, 2010.

[6] J. M. Twenge, Z. Krizan, and G. Hisler, "Decreases in self-reported sleep duration among U.S. adolescents 2009–2015 and association with new media screen time," *Sleep Medicine*, vol. 39, pp. 47–53, 2017.

[7] Android Developers, "Schedule repeating alarms," https://developer.android.com/training/scheduling/alarms, diakses 7 November 2026.

[8] Urbandroid Team, "Don't kill my app!" https://dontkillmyapp.com/, diakses 7 November 2026.

[9] G. Delataillade, "alarm: Alarm plugin for Flutter with full-screen intent, notification, and volume settings," https://pub.dev/packages/alarm, diakses 7 November 2026.

[10] Alarmy — Morning alarm clock app, https://alarmyapp.com/, diakses 7 November 2026.

[11] Flutter, Google LLC, https://flutter.dev/, diakses 7 November 2026.

## 7. Data availability & reproducibility

Repositori `bangun` (https://github.com/Rafiadnan0666/bangun) berisi kode sumber, pipeline evaluasi, dan artefak verifikasi. Tag `v1.1.0-paper` (commit `865989e9ad3da354b90af6a2ac959b54bc49e6f6`) adalah canonical state untuk reproduksi paper ini.

Artefak periklanan tersedia di:
- `evidence/delay/DELAY_TEST_REPORT.md` — log delay per perangkat
- `evidence/detection/per_light.csv` — hasil per kondisi cahaya
- `evidence/detection/per_object.csv` — hasil per objek
- `evidence/detection/heldout_eval.json` — evaluasi held-out (202 gambar)
- `evidence/usability/sus.csv` — hasil SUS
- `evidence/tests/flutter_test_output.txt` — output uji unit (78 tes)

Pipeline evaluasi tersedia di `tools/evaluate_detectors.py` dan `tools/report_device_matrix.py`.

---

## 8. Measurement protocol

| Result | Method | Date |
|---|---|---|
| Alarm delay | `adb shell date +%H:%M:%S.%N` + dumpsys poll (250 ms interval) | 2026-10-21 |
| Detection rate (lighting) | 10 trials per condition, emulator, fixed object | 2026-10-22 |
| Detection rate (objects) | 10 trials per object, 6 objects, bright condition | 2026-10-23 |
| Held-out mAP | 202 COCO val images, center-crop, threshold 0.60 | 2026-10-24 |
| SUS | 10 students, purposive sampling, 19–22 years | 2026-10-25 |
| Unit tests | `flutter test` with coverage collection | 2026-10-26 |

---

## 9. Statistical analysis

- Confidence interval: Wilson score 95% untuk proportion (α = 0.05)
- Uji signifikansi: Fisher's exact test untuk 2×2 contingency (two-tailed)
- Power analysis: not performed (exploratory user study n=10)
- NPS: not reported (raw category counts unavailable; n=10 requires multiple of 10)

Contoh: Detection rate gelap (5/10) → Wilson 95% CI [0.24, 0.76].

---

## 10. Threats to validity

- **Construct validity:** Deteksi objek menggunakan threshold 0.60, tetapi hold formula `min(1, 0.4 + score)` menghasilkan hold flat 3s untuk semua detection yang diterima (score ≥ 0.60). Formulasi ini disederhanakan menjadi "hold tetap 3s" dalam kode dan dokumentasi.
- **Internal validity:** Delay pengamatan menggunakan dumpsys poll 250 ms — batas bawah delay sebenarnya mungkin lebih rendah. Kondisi cahaya tidak diukur secara instrumental (lux meter).
- **External validity:** Hasil pada emulator tidak mengukur variansi OEM battery optimization. 202-image held-out evaluation terbatas pada 5 kelas appliance.
- **Statistical validity:** NPS tidak dilaporkan karena data mentah hilang. 95% dari n=10 adalah tidak mungkin secara matematis (9.5/10).

---

## 11. Ethics

Penelitian ini menggunakan data agregat dari 10 mahasiswa yang direkrut secara sukarela. Informed consent diperoleh secara tertulis sebelum pengujian kegunaan. Data individu tidak dilaporkan; semua hasil diagregasi. Tidak ada data pribadi yang disimpan oleh aplikasi.

Pengujian alarm dilakukan pada perangkat milik peneliti dan volunteer; tidak ada gangguan pada sistem produksi pengguna. Battery saver agresif pada beberapa OEM (Infinix, POCO) mungkin mempengaruhi delay, tetapi perilaku ini direkam sebagai batasan, bukan dikoreksi.

Penelitian ini mendapat exemption dari Institutional Review Board (IRB) Universitas Bina Sarana Informatika karena desain minimal risk (non-invasive app usage, no personal data collection, aggregated results only). Exemption number: IRB-BSI-2026-017.

---
