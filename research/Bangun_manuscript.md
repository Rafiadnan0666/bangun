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

Smartphone alarms are routinely ignored because every stage of the standard alarm interaction offers an escape: a stop button, a snooze button, a dismissible notification, or simply closing the app while it rings. This paper presents **Bangun**, an Android alarm application whose ringing state has exactly one exit: completing a challenge chosen by the user. Two gates are implemented. The **math gate** procedurally generates integer-safe arithmetic puzzles — single-operation warm-ups, two-step problems, and nested-precedence items — with a session exclusion set that prevents memorization. The **scan gate** requires holding a real object, chosen from COCO classes, inside the camera frame for three continuous seconds; detection runs fully on-device with a quantized SSD MobileNet v1 TensorFlow Lite model (300×300 uint8 input, 10 post-NMS detections, 4.0 MiB) over YUV420 frames converted through a fixed-point BT.601 square crop. Lockdown is engineered across four layers: the notification is rendered without stop or snooze buttons, ringing survives process termination, the volume floor is enforced at 35%, and `Alarm.stop()` is called only by the challenge-complete handler. The app passes static analysis (`flutter analyze`, zero issues) and 11 unit tests covering the math grammar and the scheduling model, and builds an installable debug APK. No user study is reported; the paper documents the design, the platform constraints, the verification artifacts, and explicit threats to validity, including force-stop, reboots, and the 90-class coverage of the detector.

**Keywords:** alarm application, on-device object detection, TensorFlow Lite, SSD MobileNet, procedural content generation, Android exact alarms

## Abstrak

Alarm smartphone rutin diabaikan karena setiap tahap interaksi alarm standar menyediakan pintu keluar: tombol stop, tombol snooze, notifikasi yang bisa ditolak, atau menutup aplikasi saat alarm berbunyi. Makalah ini menyajikan **Bangun**, aplikasi alarm Android yang menyediakan satu pintu keluar dari keadaan berbunyi: menyelesaikan tantangan yang dipilih pengguna sendiri. Dua gerbang diimplementasikan. **Gerbang matematika** membangkitkan soal aritmetika prosedural yang aman-bilangan-bulat, dengan tingkat kesulitan yang naik dan himpunan eksklusi yang mencegah hafalan dalam satu sesi. **Gerbang pemindaian** menuntut pengguna menahan objek fisik, dipilih dari kelas COCO, di dalam bingkai kamera selama tiga detik kontinu. Deteksi berjalan sepenuhnya on-device dengan model SSD MobileNet v1 terkuantisasi TensorFlow Lite: input 300×300 uint8, sepuluh deteksi pasca-NMS, ukuran 4,0 MiB. Frame kamera YUV420 dikonversi lewat pemotongan persegi dan aritmetika tetap BT.601. Semantik kunci akhir direkayasa pada empat lapisan: notifikasi dirender tanpa tombol stop maupun snooze, bunyi bertahan saat proses dimatikan, lantai volume dijaga pada 35%, dan `Alarm.stop()` hanya dipanggil oleh handler penyelesaian tantangan. Aplikasi lolos analisis statis (`flutter analyze`, nol isu) dan 11 uji unit, dan menghasilkan APK debug yang dapat dipasang. Belum ada evaluasi pengguna; makalah ini mendokumentasikan desain, kendala platform, artefak verifikasi, dan ancaman validitas secara eksplisit — termasuk force-stop, reboot, dan batasan 90 kelas detektor.

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

Sisa naskah: Bagian 2 membahas pustaka dan kesenjangan. Bagian 3 menjelaskan metodologi dan verifikasi. Bagian 4 menyajikan hasil dan ancaman validitas. Bagian 5 menutup.

## 2. Tinjauan Pustaka

### 2.1 Perilaku bangun dan aplikasi alarm

Penggunaan media elektronik berhubungan dengan kurangnya waktu tidur dan kualitas istirahat yang buruk [5], [6]. Pagi hari adalah titik lemah rantai disiplin tidur: di aplikasi umum, menghentikan alarm justru lebih mudah daripada mengikuti aturannya. Aplikasi komersial merespons dengan fitur gerbang, seperti soal matematika dan foto tempat tidur [10]. Akan tetapi, perilaku gerbang tidak dibahas dalam literatur: berapa sering gerbang diakali (alarm dimatikan paksa atau aplikasi dicopot), seberapa berat biaya kognitifnya bagi pengguna yang setengah sadar, dan bagaimana desainnya memengaruhi hasil itu, tidak dilaporkan. Kami tidak menemukan naskah akademis yang membahas gerbang alarm dengan detail implementasi; kesenjangan ini yang kami isi di Bagian 2.4 dan Bagian 5.

### 2.2 Computer vision ringan di ponsel

SSD (Liu dkk., 2016) adalah arsitektur deteksi objek single-shot yang cukup ringan untuk dijalankan on-device [2]. MobileNet (Howard dkk., 2017) menyumbang backbone depthwise yang memangkas komputasi dengan kerugian akurasi yang masih dapat diterima [3]. TensorFlow Lite, yang kini berkembang sebagai LiteRT, menyediakan kuantisasi pasca-pelatihan sehingga model dikemas ringkas dan dapat berjalan offline [4]. Model SSD MobileNet v1 terkuantisasi (input 300×300 uint8, sepuluh deteksi pasca-NMS) tersedia di model zoo, dan kelasnya berasal dari COCO 2014 (90 kelas) [1]. Penggunaan umum pada ponsel adalah fitur berbasis foto atau OCR. Penggunaan sebagai gerbang kendali perilaku — deteksi objek nyata yang ditunjukkan oleh pengguna, dengan keputusan yang berkonsekuensi (alarm masih berbunyi) — jarang didokumentasikan.

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

Aturan "tidak bisa dihentikan" diekayuh pada empat lapisan:

1. **Notifikasi.** `NotificationSettings` memakai `stopButton: null`, `androidSnoozeButton: null`, dan `androidStopAlarmOnDismiss: false`. Hasilnya, notifikasi berbunyi tanpa tombol hentikan dan tidak bisa diabaikan.
2. **Proses.** Pengaturan Android `androidStopAlarmOnTermination: false` menjaga bunyi tetap hidup ketika proses Flutter mati. `allowAlarmOverlap: false` dan kategori `androidAlarmClock: true` menyeragamkan perilaku ke aplikasi jam alarm.
3. **UI.** `RingScreen` dan kedua layar tantangan memakai `PopScope(canPop: false)`. Tombol back dan gestur tidak bernavigasi; percobaan keluar hanya menghasilkan getar.
4. **Audio.** `VolumeSettings.fixed(volumeEnforced: true)` dengan lantai 0,35 menjaga siren tetap terdengar meskipun volume media diturunkan.

Identitas alarm berupa bilangan bulat dari `DateTime.now().millisecondsSinceEpoch % 2147483000`. Id `0` dicadangkan untuk tantangan peraga di beranda: mesin tantangan yang sama, tanpa menyentuh penjadwalan. Saat alarm berbunyi, router level-aplikasi membuka `RingScreen` dengan nama rute `/ring`. Observer memastikan tidak ada dua layar ring bertumpuk. Peristiwa dari sistem, seperti `AlarmDropped` saat jendela boot ditolak, memicu penjadwalan ulang otomatis.

### 3.3 Gerbang matematika (RQ3)

`MathEngine` membangkitkan soal dari posisi soal dalam sesi dan jumlah total soal yang dikonfigurasi: 3, 5, atau 7 soal. Tingkatnya:

- **Warm-up (±40% soal pertama):** satu operasi — `a+b`, `a−b`, `a×b`, dan pembagian eksak;
- **Sharp (±32% berikutnya):** dua langkah, kadang bertanda kurung;
- **Brain-melt (sisanya):** rangkaian presisi bertingkat hingga lima operand.

Semua tingkat aman-bilangan-bulat *by construction*. Pembagian selalu dibentuk dari kelipatan eksak (`n×q` dibagi `n`). Pengurangan dibatasi rentangnya agar hasil tidak negatif. Bentuk `(a×b) − (c×d)` mengurutkan kedua sisi terlebih dahulu, sehingga hasilnya selalu non-negatif. Ketahanan hafalan dijaga himpunan `exclude`: setiap prompt yang dipakai dicatat, dan pembangkit mengulang hingga 128 kali untuk membuat prompt baru. Invarian ini diuji otomatis; lihat Bagian 3.5.

### 3.4 Gerbang pemindaian (RQ2)

Pipeline pemindaian berjalan real-time dan tanpa jaringan:

1. Kamera mengirim frame `yuv420` pada resolusi medium yang di-throttle 110 ms (±9 fps).
2. Setiap frame dikonversi oleh `yuvToSquareRgb`: aritmetika bilangan tetap BT.601 (skala ×1024), pemotongan persegi terpusat, sadar orientasi sensor 0/90/180/270°, dan keluaran byte mentah 0–255 tanpa normalisasi CPU karena parameter kuantisasi tercantum di dalam model.
3. Interpreter TFLite menjalankan inferensi, dan keluaran didekode menjadi `boxes`, `classes`, `scores`, dan `num` (sepuluh deteksi).
4. Sesi penahanan menghitung progres: frame yang cocok menambah waktu kehadiran berbobot score (`0.4 + score`); frame yang gagal mengurangi dua kali lebih cepat; delta per frame dibatasi ≤400 ms sehingga berada di latar tidak memberi progres gratis. Gerbang terbuka ketika kehadiran kontinu mencapai 3.000 ms.

Tabel 2 merangkum parameter model dan gerbang.

**Tabel 2.** Parameter model dan gerbang.

| Parameter | Nilai |
|---|---|
| Arsitektur | SSD MobileNet v1 [2], [3] |
| Input | `300×300×3`, uint8 terkuantisasi |
| Deteksi maksimum | 10 pasca-NMS |
| Ukuran berkas model | 4.183.312 byte (≈4,0 MiB) |
| Kelas | 90 kelas COCO [1] |
| Eksekusi | TFLite/LiteRT [4] pada CPU |
| Throttle frame | 110 ms |
| Batas delta gerbang | ≤400 ms |
| Bobot frame cocok | `0.4 + score` |
| Penyusutan frame gagal | 2× |
| Ambang penahanan | 3.000 ms kontinu |

### 3.5 Verifikasi

Verifikasi bertumpu pada tiga artefak:

1. **Analisis statis.** `flutter analyze` pada Flutter 3.47.6 / Dart 3.13.5 menghasilkan nol isu.
2. **Uji unit (11 lulus).** Mencakup: (a) sweep invarian jawaban non-negatif dan bulat-aman pada lebih dari 1.000 generasi untuk setiap jumlah soal (3, 5, 7); (b) pemetaan tingkat untuk urutan tujuh soal; (c) eksklusi prompt dalam satu sesi; (d) JSON round-trip model alarm (jam, hari, tantangan, suara, tautan Spotify, volume, tanggal); (e) semantik `nextOccurrence` untuk mode sekali, setiap hari, dan hari terpilih; (f) pembukuan statistik — streak, total, dan ledger per jenis.
3. **Build.** `flutter build apk --debug` menghasilkan APK yang dapat dipasang: compileSdk 36, AGP 9.1.0, Kotlin JVM 17.

Catatan kendala build yang kami temui (dan diatasi): `permission_handler` dipatok pada jalur 12.x karena modul android 14.x menuntut compileSdk 37, di atas rekomendasi AGP 9.1 (36). `google_fonts` dipatok pada jalur 6.x karena seri 9.x mengembalikan tipe `material_ui` yang tak dapat diterima `ThemeData` SDK saat ini. Dep `org.tensorflow:tensorflow-lite` manual dihapus karena tflite_flutter sudah menyertakan runtime LiteRT sendiri dan AGP menuntut keunikan namespace manifest.

Kami **tidak** mengklaim studi pengguna, akurasi lapangan per perangkat, atau efek perilaku — lihat Bagian 4.2.

## 4. Hasil dan Pembahasan

### 4.1 Hasil artefak

Semua hasil verifikasi Bagian 3.5 tercapai: analisis statis nol isu; 11 uji unit lulus, termasuk sweep lebih dari 1.000 generasi soal tanpa jawaban negatif dan tanpa prompt ganda; dan APK debug berhasil dibangun. Hasil direkam pada 21 Oktober 2026 dengan lockfile `pubspec.lock` yang disertakan, sehingga pemeriksa dapat mereproduksi tiga artefak itu secara langsung.

Kunci hasil desain yang lain: (a) tiga layar gerbang (ring, math, scan) semuanya memblok navigasi keluar; (b) satu-satunya jalur pemanggilan `Alarm.stop()` adalah handler penyelesaian tantangan, yang dapat diverifikasi lewat grep pada repositori; (c) tidak ada izin jaringan pada manifest, jadi setiap klaim "sepenuhnya on-device" melekat pada paket, bukan sekadar kebijakan.

### 4.2 Ancaman validitas dan jalur manipulasi yang tersisa

Desain ini tahan terhadap jalur manipulasi umum — tutup notifikasi, tombol back, turun volume, proses dimatikan. Namun, beberapa jalur tetap terbuka, dan kami menyatakannya terbuka:

- **Force-stop.** `Pengaturan → Aplikasi → Force stop` membatalkan alarm `AlarmManager` yang terjadwal, tanpa konfirmasi pengguna. Mitigasinya di luar kontrol aplikasi; ini kebiasaan semua aplikasi alarm Android dan didokumentasikan komunitas [8]. Layanan notification-on-kill plugin hanya memperingatkan, bukan mencegah.
- **Reboot.** Setelah boot, `RECEIVE_BOOT_COMPLETED` memasang kembali alarm yang persistensi native-nya disimpan plugin [9]. Verifikasi penuh pada perangkat nyata direncanakan (lihat Bagian 5).
- **Mematikan ponsel atau mencopot aplikasi.** Fondasinya: tidak ada aplikasi yang dapat mencegah kedua aksi ini. Risiko diterima dan dinyatakan, bukan disembunyikan.
- **Salah sasaran detektor.** Kelas COCO berjumlah 90; target di luar daftar tidak mungkin dibuat karena antarmuka membatasi pilihan ke kelas bernama. Perilaku pada kondisi sulit — gelap, permukaan mengkilap, objek hasil cetak — belum diukur formal. Desain penahanan berbobot score dengan penyusutan dua kali membatasi dampak satu-dua frame salah, tetapi ini bukan klaim akurasi.
- **Mode Spotify.** Mode ini best-effort. Aplikasi terus membunyikan siren lokal dan menampilkan tombol tautan; jika Spotify tidak terpasang atau tautan gagal, siren tetap bunyi. Keterbatasan ini dinyatakan di dalam aplikasi, di README, dan di sini.

Tiga klaim yang sengaja tidak kami buat: efektivitas perilaku, akurasi lapangan detektor, dan perbandingan dengan aplikasi komersial. Semuanya butuh evaluasi yang belum dilakukan.

### 4.3 Implikasi

Bagi peneliti, fungsi repositori ini sebagai basis replikasi yang murah: semua konstanta gerbang tertulis di kode, tertutup uji otomatis, dan didokumentasikan di makalah ini. Bagi praktisi, poin yang dapat dibawa adalah pilihan arsitektur: semantik penguncian dicapai tanpa pekerjaan native tambahan di samping penjadwalan, dan deteksi berjalan sepenuhnya di perangkat dengan model 4 MiB tanpa izin jaringan.

## 5. Kesimpulan dan Rencana Lanjutan

Bangun menunjukkan bahwa aplikasi alarm Android dapat dirancang agar satu-satunya pintu keluar dari keadaan berbunyi adalah menyelesaikan tantangan yang dipilih sendiri: matematika prosedural atau pemindaian objek on-device. Ini dicapai dengan memanfaatkan plugin penjadwalan asli, bukan pekerjaan native ad-hoc. Verifikasi yang telah dilakukan: analisis statis nol isu, 11 uji unit lulus, dan APK debug yang dapat dipasang.

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

[7] Android Developers, "Schedule repeating alarms," https://developer.android.com/training/scheduling/alarms, diakses 21 Oktober 2026.

[8] Urbandroid Team, "Don't kill my app!" https://dontkillmyapp.com/, diakses 21 Oktober 2026.

[9] G. Delataillade, "alarm: Alarm plugin for Flutter with full-screen intent, notification, and volume settings," https://pub.dev/packages/alarm, diakses 21 Oktober 2026.

[10] Alarmy — Morning alarm clock app, https://alarmyapp.com/, diakses 21 Oktober 2026.

[11] Flutter, Google LLC, https://flutter.dev/, diakses 21 Oktober 2026.
