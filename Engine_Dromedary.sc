// Engine_Dromedary2.sc — robust arg parsing + live level mix
// Place in: ~/dust/code/dronedrone/Engine_Dromedary2.sc
//
// IMPORTANT: This file is the exact logic you provided, with formatting and
// explanatory comments only. No functional code changes were made.

Engine_Dromedary2 : CroneEngine {
  var <voices, group;

  // --------------------------------------------------------------------------
  // Global state (mutable parameters cached on the engine side)
  // --------------------------------------------------------------------------
  var atk = 0.5, dec = 1.0, sus = 0.8, rel = 2.0; // ADSR defaults
  var mainLevel = 1.0, mainWave = 0;                // 0..3: sine/tri/saw/square
  var subLevel = 0.5, subDetune = 0.0, subWave = 0; // semitone spread around sub octave
  var cutoff = 12000, rq = 0.2;                     // 0.05..0.99 (lower = sharper)
  var noiseLevel = 0.1, chorusMix = 0.2;            // noise + stereo chorus
  var rvbMix = 0.25, rvbRoom = 0.6, rvbDamp = 0.5;  // FreeVerb2 mix/room/damp

  // Limiter (global defaults applied to every voice)
  var limitOn = 1, limitThresh = 0.98, limitDur = 0.01;

  *new { ^super.new }

  alloc {
    var lastNumber, lastInt, getNums; // helper readers for robust/forgiving args

    ("[Dromedary2 robust] " ++ this.class.filenameSymbol.asString).postln;

    // All synths live under this group
    group  = Group.head(Server.default);

    // Track active voices by id → Synth mapping
    voices = IdentityDictionary.new;

    // ------------------------------------------------------------------------
    // Robust readers (work with typed args OR full OSC arrays)
    // - lastNumber: return the last numeric from a possibly-mixed list
    // - lastInt:    lastNumber, then round → integer
    // - getNums:    return all numbers from a mixed list
    // These helpers allow calls like: engine.cutoff(1200) or engine.cutoff({"cutoff",1200})
    // or even engine.cutoff({"cutoff", 1, 2, 3, 1200}).
    // ------------------------------------------------------------------------
    lastNumber = { |arglist, default=0.0|
      var lst, num;
      lst = arglist;
      if(lst.isKindOf(Array).not) { lst = [lst] };
      if(lst.size > 0 and: { lst[0].isKindOf(Symbol) }) {
        lst = lst.copyRange(1, lst.size-1);
      };
      lst = lst.flatten;
      num = lst.reverse.detect({ |e| e.isKindOf(Number) });
      (num ? default).asFloat;
    };

    lastInt = { |arglist, default=0|
      var n;
      n = lastNumber.(arglist, default);
      n.round.asInteger;
    };

    getNums = { |arglist|
      var lst;
      lst = arglist;
      if(lst.isKindOf(Array).not) { lst = [lst] };
      if(lst.size > 0 and: { lst[0].isKindOf(Symbol) }) {
        lst = lst.copyRange(1, lst.size-1);
      };
      lst = lst.flatten;
      lst.select({ |e| e.isKindOf(Number) });
    };

    // ------------------------------------------------------------------------
    // DRONE VOICE SynthDef
    // - Per-voice ADSR + main waveform + sub-osc blend + noise + LPF + chorus
    // - FreeVerb2 on the tail, optional Limiter at the output
    // ------------------------------------------------------------------------
 
// --- DRONE VOICE ---
SynthDef(\dromedaryVoice2, { |out=0, id=0, freq=220, amp=0.5, gate=1,
  atk=0.5, dec=1.0, sus=0.8, rel=2.0,
  mainLevel=1.0, mainWave=0,
  subLevel=0.5, subDetune=0.0, subWave=0,
  cutoff=12000, rq=0.2,
  noiseLevel=0.1, chorusMix=0.2,
  rvbMix=0.25, rvbRoom=0.6, rvbDamp=0.5,
  // limiter args
  limitOn=1, limitThresh=0.98, limitDur=0.01,
  // NEW: pan + post-fx level
  pan=0, level=1.0 |

  var env, mainOsc, subBase, detRatio, subUp, subDn, subMix, noise,
      pre, filt, maxDelay, lfo1, lfo2, wetL, wetR, chorus, envd,
      balanced, withVerb, outSig;

  env = Env.adsr(atk, dec, sus, rel).kr(gate, doneAction:2);

  mainOsc = Select.ar(mainWave.clip(0,3), [
    SinOsc.ar(freq), LFTri.ar(freq), Saw.ar(freq), Pulse.ar(freq, 0.5)
  ]) * mainLevel;

  subBase  = freq * 0.5;
  detRatio = (2 ** (subDetune / 12)).max(1.0);
  subUp = Select.ar(subWave.clip(0,3), [
    SinOsc.ar(subBase * detRatio), LFTri.ar(subBase * detRatio),
    Saw.ar(subBase * detRatio),    Pulse.ar(subBase * detRatio, 0.5)
  ]);
  subDn = Select.ar(subWave.clip(0,3), [
    SinOsc.ar(subBase / detRatio), LFTri.ar(subBase / detRatio),
    Saw.ar(subBase / detRatio),    Pulse.ar(subBase / detRatio, 0.5)
  ]);
  subMix = ((subUp + subDn) * 0.5) * subLevel;

  noise = WhiteNoise.ar(noiseLevel);

  pre  = (mainOsc + subMix + noise) * amp;
  filt = RLPF.ar(pre, cutoff, rq.clip(0.05, 0.99));

  maxDelay = 0.02;
  lfo1 = SinOsc.kr(0.13 + (id % 5) * 0.01, 0, 0.003, 0.004);
  lfo2 = SinOsc.kr(0.17 + (id % 7) * 0.008, 0, 0.004, 0.006);
  wetL = DelayC.ar(filt, maxDelay, lfo1);
  wetR = DelayC.ar(filt, maxDelay, lfo2);
  chorus = (filt ! 2) * (1 - chorusMix) + [wetL, wetR] * chorusMix;

  envd = chorus * env;

  // stereo pan then reverb
  balanced = Balance2.ar(envd[0], envd[1], pan.clip(-1, 1));
  withVerb = FreeVerb2.ar(balanced[0], balanced[1], rvbMix, rvbRoom, rvbDamp);

  // post-chain level for Mix page
  withVerb = withVerb * level;

  // limiter (UGen-safe select)
  outSig = Select.ar(
    (limitOn > 0),
    [ withVerb, Limiter.ar(withVerb, limitThresh, limitDur) ]
  );

  Out.ar(out, outSig);
}).add;

    // ------------------------------------------------------------------------
    // 808-ish KICK SynthDef
    // - Simple sine body with click, light tanh drive, optional limiter
    // ------------------------------------------------------------------------
    SynthDef(\dromedaryKick2, { |out=0, amp=0.9, tune=48, decay=0.60, bend=2.2, click=0.03, body=1.0, tone=100,
      // limiter args
      limitOn=1, limitThresh=0.98, limitDur=0.01 |
      var env, pEnv, toneSig, cEnv, clickSig, sig;  // local buffers

      // main amp env
      env  = Env.perc(0.002, decay, 1.0, curve:-6).ar(doneAction:2);

      // pitch env
      pEnv = Env([tune * bend, tune * 1.1, tune], [0.03, decay - 0.03], curve:[-8, -5]).ar;

      // body
      toneSig = SinOsc.ar(pEnv) * env * body;
      toneSig = LPF.ar(toneSig, tone.max(60));
      toneSig = HPF.ar(toneSig, 25);

      // click
      cEnv = Env.perc(0.0005, 0.012).ar;
      clickSig = LPF.ar(WhiteNoise.ar(click) * cEnv, 3000);

      // glue + amp
      sig = toneSig + clickSig;
      sig = tanh(sig * 1.2) * amp;

      // limiter (mono), then make stereo
sig = Select.ar(
  (limitOn > 0),  // 0 or 1 (kr)
  [ sig, Limiter.ar(sig, limitThresh, limitDur) ]
);

      Out.ar(out, sig ! 2);
    }).add;

    // ------------------------------------------------------------------------
    // COMMANDS (robust): named OSC commands exposed to norns Lua
    // Each command accepts either typed args or an OSC array payload.
    // ------------------------------------------------------------------------

    // Envelope
    this.addCommand("attack",  "f", { |q| atk = lastNumber.(q, atk).max(0) });
    this.addCommand("decay",   "f", { |q| dec = lastNumber.(q, dec).max(0) });
    this.addCommand("sustain", "f", { |q| sus = lastNumber.(q, sus).clip(0,1) });
    this.addCommand("release", "f", { |q| rel = lastNumber.(q, rel).max(0) });

    // Tone + mix
    this.addCommand("mainOscLevel", "f", { |q| mainLevel = lastNumber.(q, mainLevel).max(0) });
    this.addCommand("oscWaveShape", "i", { |q| mainWave  = lastInt.(q, mainWave).clip(0,3) });

    this.addCommand("subOscLevel",  "f", { |q| subLevel  = lastNumber.(q, subLevel).clip(0,1) });
    this.addCommand("subOscDetune", "f", { |q| subDetune = lastNumber.(q, subDetune).clip(0,24) });
    this.addCommand("subOscWave",   "i", { |q| subWave   = lastInt.(q, subWave).clip(0,3) });

    this.addCommand("noiseLevel",   "f", { |q| noiseLevel = lastNumber.(q, noiseLevel).clip(0,1) });
    this.addCommand("chorusMix",    "f", { |q| chorusMix  = lastNumber.(q, chorusMix).clip(0,1) });

    // Filter
    this.addCommand("cutoff",    "f", { |q| cutoff = lastNumber.(q, cutoff).clip(20, 20000) });
    this.addCommand("resonance", "f", { |q| rq     = lastNumber.(q, rq).clip(0.05, 0.99) });

    // Reverb
    this.addCommand("reverbMix",  "f", { |q| rvbMix  = lastNumber.(q, rvbMix).clip(0,1) });
    this.addCommand("reverbRoom", "f", { |q| rvbRoom = lastNumber.(q, rvbRoom).clip(0,1) });
    this.addCommand("reverbDamp", "f", { |q| rvbDamp = lastNumber.(q, rvbDamp).clip(0,1) });

    // ----------------------------------------------------------------------
    // noteOn: start/replace a voice at a specific id; ensures no stacks
    // - Args (robust): id, freq, amp (can arrive wrapped in arrays)
    // - If a voice already exists at id, it is freed (no tail)
    // ----------------------------------------------------------------------
    this.addCommand("noteOn", "iff", { |...args|
      var lst, nums, id, freq, amp, old, synth;

      lst = args;
      if(lst.size == 1 and: { lst[0].isKindOf(Array) }) { lst = lst[0] };
      if(lst.size > 0 and: { lst[0].isKindOf(Symbol) }) { lst = lst.copyRange(1, lst.size-1) };
      lst = lst.flatten;

      nums = List.new; lst.do({ |e| if(e.isKindOf(Number)) { nums.add(e) } });
      if(nums.size >= 3) {
        id   = nums.at(nums.size-3).asInteger;
        freq = nums.at(nums.size-2).asFloat;
        amp  = nums.at(nums.size-1).asFloat;
      }{
        id = 1001; freq = 220.0; amp = 0.5;
      };

      // de-dupe: if a voice already exists at this id, kill it first
      old = voices.at(id);
      if(old.notNil) {
        old.set(\gate, 0);
        old.free;                 // hard-free so there’s no envelope tail
        voices.removeAt(id);
      };

      // Spawn fresh voice with all current engine-global settings
      synth = Synth.tail(group, \dromedaryVoice2, [
        \id, id, \freq, freq, \amp, amp,
        \atk, atk, \dec, dec, \sus, sus, \rel, rel,
        \mainLevel, mainLevel, \mainWave, mainWave,
        \subLevel, subLevel, \subDetune, subDetune, \subWave, subWave,
        \cutoff, cutoff, \rq, rq,
        \noiseLevel, noiseLevel, \chorusMix, chorusMix,
        \rvbMix, rvbMix, \rvbRoom, rvbRoom, \rvbDamp, rvbDamp, 
        \limitOn, limitOn, \limitThresh, limitThresh, \limitDur, limitDur
      ]);
      voices[id] = synth;
    });

    // ----------------------------------------------------------------------
    // freeRange: HARD FREE a contiguous id range [lo..hi]
    // - Immediate kill (no tail) and remove entries from the voices map
    // ----------------------------------------------------------------------
    this.addCommand("freeRange", "ii", { |lo, hi|
      var rm = Array.new;
      voices.keysValuesDo { |k, s|
        if(k >= lo and: { k <= hi }) {
          if(s.notNil) { s.free };
          rm = rm.add(k);
        };
      };
      rm.do { |k| voices.removeAt(k) };
    });

    // Single id soft noteOff (let envelope release)
    this.addCommand("noteOff", "i", { |q|
      var id, s;
      id = lastInt.(q, -1);
      s = voices.at(id);
      if(s.notNil) { s.set(\gate, 0); voices.removeAt(id) };
    });

    // noteOffRange: soft release across [lo..hi]
    this.addCommand("noteOffRange", "ii", { |lo, hi|
      var killKeys = Array.new;
      voices.keysValuesDo({ |k, s|
        if(k >= lo and: { k <= hi }) {
          if(s.notNil) { s.set(\gate, 0) };
          killKeys = killKeys.add(k);
        }
      });
      killKeys.do({ |k| voices.removeAt(k) });
    });

    // ----------------------------------------------------------------------
    // Live mixing: setLevelRange / setLevelId (post-chain level preferred)
    // ----------------------------------------------------------------------
    this.addCommand("setLevelRange", "iif", { |q|
      var nums, lo, hi, level, a;
      nums = getNums.(q);
      lo    = (nums.size >= 3).if({ nums.at(nums.size-3).asInteger }, { 1 });
      hi    = (nums.size >= 3).if({ nums.at(nums.size-2).asInteger }, { 0 });
      level = (nums.size >= 3).if({ nums.at(nums.size-1).asFloat   }, { 1.0 });
      a = level.clip(0, 1.5);
      voices.keysValuesDo { |k, s|
        if(k >= lo and: { k <= hi }) { if(s.notNil) { s.set(\level, a) } };
      };
    });

    this.addCommand("setLevelId", "if", { |q|
      var id, a, s;
      id = lastInt.(q, -1);
      a  = lastNumber.(q, 1.0).clip(0, 1.5);
      s = voices.at(id);
      if(s.notNil) { s.set(\level, a) };
    });

    // ----------------------------------------------------------------------
    // Global limiter controls (propagate to every active voice)
    // NOTE: The following three commands appear twice in your source; kept as-is.
    // ----------------------------------------------------------------------
    this.addCommand("limitOn", "i", { |...args|
      limitOn = lastInt.(args, limitOn).clip(0, 1);
      voices.do { |assoc| var s = assoc.value; if(s.notNil) { s.set(\limitOn, limitOn) } };
    });

    this.addCommand("limitThresh", "f", { |...args|
      limitThresh = lastNumber.(args, limitThresh).clip(0.5, 2.0);
      voices.do { |assoc| var s = assoc.value; if(s.notNil) { s.set(\limitThresh, limitThresh) } };
    });

    this.addCommand("limitDur", "f", { |...args|
      limitDur = lastNumber.(args, limitDur).clip(0.0, 0.05);
      voices.do { |assoc| var s = assoc.value; if(s.notNil) { s.set(\limitDur, limitDur) } };
    });

    // Optional: pre-chain amp (back-compat with older mixers)
    this.addCommand("setAmpRange", "iif", { |q|
      var nums, lo, hi, amp, a;
      nums = getNums.(q);
      lo  = (nums.size >= 3).if({ nums.at(nums.size-3).asInteger }, { 1 });
      hi  = (nums.size >= 3).if({ nums.at(nums.size-2).asInteger }, { 0 });
      amp = (nums.size >= 3).if({ nums.at(nums.size-1).asFloat   }, { 1.0 });
      a = amp.clip(0, 1.5);
      voices.keysValuesDo { |k, s|
        if(k >= lo and: { k <= hi }) { if(s.notNil) { s.set(\amp, a) } };
      };
    });

    this.addCommand("setAmpId", "if", { |q|
      var id, a, s;
      id = lastInt.(q, -1);
      a  = lastNumber.(q, 1.0).clip(0, 1.5);
      s = voices.at(id);
      if(s.notNil) { s.set(\amp, a) };
    });

    // Kick trigger (808-ish)
    this.addCommand("kick", "fff", { |q|
      var nums, a, t, d;
      nums = getNums.(q);
      a = (nums.size >= 3).if({ nums.at(nums.size-3).asFloat }, { 0.9 });
      t = (nums.size >= 3).if({ nums.at(nums.size-2).asFloat }, { 48.0 });
      d = (nums.size >= 3).if({ nums.at(nums.size-1).asFloat }, { 0.60 });
      Synth.tail(group, \dromedaryKick2, [\amp, a, \tune, t, \decay, d, \limitOn, limitOn, \limitThresh, limitThresh, \limitDur, limitDur]);
    });

    // ----------------------------------------------------------------------
    // PAN control for a single id and for a range
    // ----------------------------------------------------------------------
    this.addCommand("setPanId", "if", { |id, pan|
      var s = voices.at(id);
      if(s.notNil) { s.set(\pan, pan.clip(-1.0, 1.0)) };
    });

    this.addCommand("setPanRange", "iif", { |lo, hi, pan|
      var v = pan.clip(-1.0, 1.0);
      voices.keysValuesDo { |k, s|
        if(k >= lo and: { k <= hi }) { if(s.notNil) { s.set(\pan, v) } };
      };
    });

    // --- Limiter threshold (apply to all active voices) [duplicate kept]
    this.addCommand("limitThresh", "f", { |t|
      var v = t.clip(0.1, 1.5);
      voices.do { |assoc| var s = assoc.value; if(s.notNil) { s.set(\limitThresh, v) } };
    });

    // (optional) change limiter attack/lookahead globally [duplicate kept]
    this.addCommand("limitDur", "f", { |d|
      var v = d.clip(0.001, 0.2);
      voices.do { |assoc| var s = assoc.value; if(s.notNil) { s.set(\limitDur, v) } };
    });

    // ----------------------------------------------------------------------
    // Utilities
    // ----------------------------------------------------------------------
    this.addCommand("free_all_notes", "", {
      voices.keysValuesDo { |k, s| if(s.notNil) { s.set(\gate, 0) } };
      voices.clear;
    });

    this.addCommand("panic", "", {
      group.freeAll;                  // kill everything in the engine group
      voices = IdentityDictionary.new;
    });
  }

  // --------------------------------------------------------------------------
  // Engine teardown
  // --------------------------------------------------------------------------
  free {
    voices.keysValuesDo { |k, s| if(s.notNil) { s.free } };
    voices.clear;
    group.free;
    super.free;
  }
}
