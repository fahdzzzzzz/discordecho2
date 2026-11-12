<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Discord EAX Sound Control</title>
    <!-- Tailwind CSS for modern styling and animations -->
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <style>
        body {
            font-family: 'Inter', sans-serif;
            background: linear-gradient(135deg, #0f172a 0%, #1e1b4b 100%);
            min-height: 100vh;
        }
        /* Glassmorphism styling for iOS feel */
        .ios-glass {
            background: rgba(30, 41, 59, 0.75);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        .ios-panel {
            background: rgba(15, 23, 42, 0.85);
            backdrop-filter: blur(25px);
            -webkit-backdrop-filter: blur(25px);
            border: 1px solid rgba(255, 255, 255, 0.12);
        }
        /* Custom range slider styling */
        input[type=range] {
            -webkit-appearance: none;
            width: 100%;
            background: transparent;
        }
        input[type=range]:focus {
            outline: none;
        }
        input[type=range]::-webkit-slider-runnable-track {
            width: 100%;
            height: 6px;
            cursor: pointer;
            background: rgba(255, 255, 255, 0.15);
            border-radius: 3px;
        }
        input[type=range]::-webkit-slider-thumb {
            height: 22px;
            width: 22px;
            border-radius: 50%;
            background: #38bdf8;
            cursor: pointer;
            -webkit-appearance: none;
            margin-top: -8px;
            box-shadow: 0 2px 6px rgba(56, 189, 248, 0.4);
            transition: transform 0.1s ease, background-color 0.1s ease;
        }
        input[type=range]::-webkit-slider-thumb:hover {
            transform: scale(1.1);
            background: #0ea5e9;
        }
        /* Smooth fade & scale transition */
        .panel-transition {
            transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
        }
    </style>
</head>
<body class="text-white flex items-center justify-center p-4">

    <!-- Mock Discord App Environment Container -->
    <div class="relative w-full max-w-md h-[700px] rounded-[40px] overflow-hidden shadow-2xl border-4 border-slate-700/50 flex flex-col justify-between bg-slate-900">
        
        <!-- Fake Discord Header -->
        <div class="px-6 py-4 bg-slate-800/80 border-b border-slate-700/50 flex items-center justify-between">
            <div class="flex items-center space-x-3 space-x-reverse">
                <div class="w-10 h-10 rounded-full bg-indigo-600 flex items-center justify-center font-bold text-lg shadow-inner">💬</div>
                <div>
                    <h2 class="font-semibold text-sm">غرفة الدردشة الصوتية</h2>
                    <p class="text-xs text-emerald-400 flex items-center gap-1 mt-0.5">
                        <span class="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span> متصل (EAX نشط)
                    </p>
                </div>
            </div>
            <div class="text-slate-400 text-sm">#general</div>
        </div>

        <!-- Chat Body Mock Content -->
        <div class="p-6 flex-1 overflow-y-auto space-y-4">
            <div class="flex items-start gap-3">
                <div class="w-8 h-8 rounded-full bg-sky-600 flex items-center justify-center text-xs font-bold">فهد</div>
                <div class="ios-glass p-3 rounded-2xl rounded-tr-none text-sm max-w-[80%]">
                    السلام عليكم يا شباب، كيف الصوت الحين مع صدى الكهف المسكون؟ 🏔️
                </div>
            </div>
            <div class="flex items-start gap-3 flex-row-reverse">
                <div class="w-8 h-8 rounded-full bg-purple-600 flex items-center justify-center text-xs font-bold">سلطان</div>
                <div class="bg-indigo-600/60 p-3 rounded-2xl rounded-tl-none text-sm max-w-[80%]">
                    الصدا خورافي وواضح جداً، كأننا في استوديو احترافي! 🎛️✨
                </div>
            </div>
            <div class="flex items-start gap-3">
                <div class="w-8 h-8 rounded-full bg-sky-600 flex items-center justify-center text-xs font-bold">فهد</div>
                <div class="ios-glass p-3 rounded-2xl rounded-tr-none text-sm max-w-[80%]">
                    استخدم الزر العائم بالأسفل عشان تعدل وزنية الصدى بنفسك في أي وقت.
                </div>
            </div>
        </div>

        <!-- Fake Discord Bottom Navigation Bar -->
        <div class="h-16 bg-slate-800/90 border-t border-slate-700/50 flex items-center justify-around px-4">
            <span class="text-xl opacity-60">🏠</span>
            <span class="text-xl opacity-60">🔍</span>
            <span class="text-xl opacity-60">🔔</span>
            <span class="text-xl opacity-100 text-sky-400 font-bold">⚙️</span>
        </div>

        <!-- Floating Action Button (FAB) (Positioned inside the app frame) -->
        <button id="fabBtn" class="absolute bottom-20 left-6 w-14 h-14 bg-gradient-to-tr from-sky-500 to-indigo-600 rounded-full shadow-lg shadow-sky-500/30 flex items-center justify-center text-2xl hover:scale-105 active:scale-95 transition-all z-30 focus:outline-none">
            🎛️
        </button>

        <!-- Sleek Floating Control Panel Card -->
        <div id="controlPanel" class="absolute bottom-36 left-6 right-6 ios-panel rounded-3xl p-5 shadow-2xl panel-transition opacity-0 pointer-events-none translate-y-4 z-40">
            
            <!-- Panel Header -->
            <div class="flex items-center justify-between mb-4 pb-3 border-b border-white/10">
                <div class="flex items-center gap-2">
                    <span class="text-xl">🎚️</span>
                    <h3 class="font-bold text-base text-white">إعدادات Creative EAX</h3>
                </div>
                <button id="closePanel" class="w-7 h-7 rounded-full bg-white/10 flex items-center justify-center text-xs hover:bg-white/20 transition-colors">✕</button>
            </div>

            <!-- 1. EAX Master Power Toggle -->
            <div class="flex items-center justify-between mb-4 bg-white/5 p-3 rounded-2xl">
                <div>
                    <span class="block text-sm font-semibold">تفعيل تأثير EAX</span>
                    <span class="text-xs text-slate-400">تشغيل معالجة الصدى الصوتية</span>
                </div>
                <label class="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" id="eaxPowerSwitch" class="sr-only peer" checked>
                    <div class="w-12 h-6 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-sky-500"></div>
                </label>
            </div>

            <!-- 2. Haunted Cavern Mode Toggle -->
            <div class="flex items-center justify-between mb-4 bg-white/5 p-3 rounded-2xl">
                <div>
                    <span class="block text-sm font-semibold">مود الكهف المسكون</span>
                    <span class="text-xs text-slate-400">صدى عميق وارتداد واسع 🏔️</span>
                </div>
                <label class="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" id="cavernSwitch" class="sr-only peer">
                    <div class="w-12 h-6 bg-slate-700 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-purple-600"></div>
                </label>
            </div>

            <!-- 3. EAX Reverb Level Slider (0-100) -->
            <div class="bg-white/5 p-3 rounded-2xl">
                <div class="flex justify-between items-center mb-2">
                    <span class="text-sm font-medium text-slate-300">مستوى الصدى (Level)</span>
                    <span id="levelValueDisplay" class="text-sm font-bold text-sky-400 bg-sky-500/10 px-2.5 py-0.5 rounded-full border border-sky-500/20">60</span>
                </div>
                <input type="range" id="eaxLevelSlider" min="0" max="100" value="60" class="w-full">
            </div>

            <!-- Notification Toast / Status Info -->
            <div id="statusToast" class="mt-4 text-center text-xs text-slate-400 bg-sky-500/10 border border-sky-500/20 py-1.5 rounded-xl transition-all">
                الحالة: يعمل بشكل طبيعي ومتوازن 🎙️
            </div>
        </div>

    </div>

    <!-- JavaScript Interactive Logic -->
    <script>
        const fabBtn = document.getElementById('fabBtn');
        const controlPanel = document.getElementById('controlPanel');
        const closePanel = document.getElementById('closePanel');
        const eaxLevelSlider = document.getElementById('eaxLevelSlider');
        const levelValueDisplay = document.getElementById('levelValueDisplay');
        const cavernSwitch = document.getElementById('cavernSwitch');
        const eaxPowerSwitch = document.getElementById('eaxPowerSwitch');
        const statusToast = document.getElementById('statusToast');

        let isPanelOpen = false;

        // Toggle Control Panel visibility
        function togglePanel() {
            isPanelOpen = !isPanelOpen;
            if (isPanelOpen) {
                controlPanel.classList.remove('opacity-0', 'pointer-events-none', 'translate-y-4');
                controlPanel.classList.add('opacity-100', 'pointer-events-auto', 'translate-y-0');
            } else {
                controlPanel.classList.remove('opacity-100', 'pointer-events-auto', 'translate-y-0');
                controlPanel.classList.add('opacity-0', 'pointer-events-none', 'translate-y-4');
            }
        }

        fabBtn.addEventListener('click', togglePanel);
        closePanel.addEventListener('click', togglePanel);

        // Update level value display dynamically
        eaxLevelSlider.addEventListener('input', (e) => {
            const val = e.target.value;
            levelValueDisplay.textContent = val;
            statusToast.textContent = `تم تحديث مستوى الصدى إلى: ${val}% 🎚️`;
        });

        // Haunted Cavern Mode interaction
        cavernSwitch.addEventListener('change', (e) => {
            if (e.target.checked) {
                eaxLevelSlider.value = 88;
                levelValueDisplay.textContent = '88';
                statusToast.textContent = '🏔️ تم تفعيل مود الكهف المسكون (ارتداد عميق)';
                statusToast.className = 'mt-4 text-center text-xs text-purple-300 bg-purple-500/10 border border-purple-500/20 py-1.5 rounded-xl transition-all';
            } else {
                eaxLevelSlider.value = 60;
                levelValueDisplay.textContent = '60';
                statusToast.textContent = '🎙️ العودة للوضع القياسي المتوازن';
                statusToast.className = 'mt-4 text-center text-xs text-sky-300 bg-sky-500/10 border border-sky-500/20 py-1.5 rounded-xl transition-all';
            }
        });

        // Master EAX Power Switch
        eaxPowerSwitch.addEventListener('change', (e) => {
            const enabled = e.target.checked;
            eaxLevelSlider.disabled = !enabled;
            cavernSwitch.disabled = !enabled;
            if (!enabled) {
                statusToast.textContent = '⚠️ تم تعطيل تأثير EAX المؤقت';
                statusToast.className = 'mt-4 text-center text-xs text-red-300 bg-red-500/10 border border-red-500/20 py-1.5 rounded-xl transition-all';
            } else {
                statusToast.textContent = '✅ تم إعادة تفعيل معالجة الصوت بنجاح';
                statusToast.className = 'mt-4 text-center text-xs text-sky-300 bg-sky-500/10 border border-sky-500/20 py-1.5 rounded-xl transition-all';
            }
        });
    </script>

</body>
</html>
