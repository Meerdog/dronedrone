// Engine_Dromedary2.sc — drones + impact-style drums with robust args
// Place in: ~/dust/code/dronedrone/Engine_Dromedary2.sc

Engine_Dromedary2 : CroneEngine {
  var <voices, group;

  // --------------------------------------------------------------------------
  // Global state (mutable parameters cached on the engine side)
  // --------------------------------------------------------------------------
  var atk = 0.5, dec = 1.0, sus = 0.8, rel = 2.0;   // ADSR defaults
  var mainLevel = 1.0, mainWave = 0;                // 0..3: sine/tri/saw/square
  var subLevel = 0.5, subDetune = 0.0, subWave = 0; // semitone spread around sub octave
  var cutoff = 12000, rq = 0.2;                     // 0.05..0.99 (lower = sharper)
  var noiseLevel = 0.1, chorusMix = 0.2;            // noise + stereo chorus
  var rvbMix = 0.25, rvbRoom = 0.6, rvbDamp = 0.5;  // FreeVerb2

  // Limiter (global defaults applied to every voice)
  var limitOn = 1, limitThresh = 0.98, limitDur = 0.01;

  *new { ^super.new }

  alloc {
    var lastNumber, lastInt, getNums; // robust readers
    var logmsg;

    logmsg = "[Dromedary2] " ++ this.class.filenameSymbol.asString;
    logmsg.postln;

    // All synths live under this group
    group  = Group.head(Server.default);

    // Track active voices by id → Synth mapping
    voices = IdentityDictionary.new;

    // ------------------------------------------------------------------------
    // Robust readers (typed args or OSC arrays)
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
    // ------------------------------------------------------------------------
    SynthDef(\dromedaryVoice2, { |out=0, id=0, freq=220, amp=0.5, gate=1,
      atk=0.5, dec=1.0, sus=0.8, rel=2.0,
      mainLevel=1.0, mainWave=0,
      subLevel=0.5, subDetune=0.0, subWave=0,
      cutoff=12000, rq=0.2,
      noiseLevel=0.1, chorusMix=0.2,
      rvbMix=0.25, rvbRoom=0.6, rvbDamp=0.5,
      // limiter args
      limitOn=1, limitThresh=0.98, limitDur=0.01,
      // pan + post-fx level
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

      // light chorus
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

      // post-chain level
      withVerb = withVerb * level;

      // limiter (UGen-safe select)
      outSig = Select.ar(
        (limitOn > 0),
        [ withVerb, Limiter.ar(withVerb, limitThresh, limitDur) ]
      );

      Out.ar(out, outSig);
    }).add;

    // ------------------------------------------------------------------------
    // DRUMS — impact-style
    // ------------------------------------------------------------------------

    // --- KICK (808-ish)
    SynthDef(\dromedaryKick2, { |out=0, amp=0.9, tune=48, decay=0.60, bend=2.2, click=0.03, body=1.0, tone=100,
      limitOn=1, limitThresh=0.98, limitDur=0.01|
      var env, pEnv, toneSig, cEnv, clickSig, sig;

      env  = Env.perc(0.002, decay, 1.0, curve:-6).ar(doneAction:2);
      pEnv = Env([tune * bend, tune * 1.1, tune], [0.03, decay - 0.03], curve:[-8, -5]).ar;

      toneSig = SinOsc.ar(pEnv) * env * body;
      toneSig = LPF.ar(toneSig, tone.max(60));
      toneSig = HPF.ar(toneSig, 25);

      cEnv = Env.perc(0.0005, 0.012).ar;
      clickSig = LPF.ar(WhiteNoise.ar(click) * cEnv, 3000);

      sig = (toneSig + clickSig);
      sig = tanh(sig * 1.2) * amp;

      sig = Select.ar((limitOn > 0), [sig, Limiter.ar(sig, limitThresh, limitDur)]);
      Out.ar(out, sig ! 2);
    }).add;

    // --- SNARE
    SynthDef(\dromedarySnare2, { |out=0, level=0.8, tone=340, snappy=1.5, decay=3.2,
      limitOn=1, limitThresh=0.98, limitDur=0.01|
      var noiseEnv, atkEnv, noise, osc1, osc2, sum, sig;
      noiseEnv = Env.perc(0.001, decay, 1, -115).ar(doneAction:2);
      atkEnv   = Env.perc(0.001, decay*0.333, curve:-95).ar;
      noise    = WhiteNoise.ar;
      noise    = HPF.ar(noise, 1800);
      noise    = LPF.ar(noise, 8850);
      noise    = noise * noiseEnv * snappy;
      osc1     = SinOsc.ar(189, pi/2) * 0.6;
      osc2     = SinOsc.ar(tone, pi/2) * 0.7;
      sum      = (osc1 + osc2) * atkEnv * level * 2;
      sig      = (noise + sum) * level * 2.5;
      sig      = HPF.ar(sig, 340);
      sig      = Select.ar((limitOn > 0), [sig, Limiter.ar(sig, limitThresh, limitDur)]);
      Out.ar(out, Pan2.ar(sig, 0));
    }).add;

    // --- CLOSED HAT
    SynthDef(\dromedaryCH2, { |out=0, level=0.9, tone=500, decay=1.5,
      limitOn=1, limitThresh=0.98, limitDur=0.01|
      var env, o1,o2,o3,o4,o5,o6, hi, lo, sig;
      env = Env.perc(0.005, decay, 1, -30).ar(doneAction:2);
      o1 = LFPulse.ar(tone + 3.52);   o2 = LFPulse.ar(tone + 166.31);
      o3 = LFPulse.ar(tone + 101.77); o4 = LFPulse.ar(tone + 318.19);
      o5 = LFPulse.ar(tone + 611.16); o6 = LFPulse.ar(tone + 338.75);
      hi = HPF.ar(BPF.ar(o1+o2+o3+o4+o5+o6, 8900, 1), 9000);
      lo = BHiPass.ar(BBandPass.ar(o1+o2+o3+o4+o5+o6, 8900, 0.8), 9000, 0.3);
      sig = BPeakEQ.ar(hi + lo, 9700, 0.8, 0.7) * env * level;
      sig = Select.ar((limitOn > 0), [sig, Limiter.ar(sig, limitThresh, limitDur)]);
      Out.ar(out, Pan2.ar(sig, 0));
    }).add;

    // --- OPEN HAT
    SynthDef(\dromedaryOH2, { |out=0, level=0.9, tone=400, decay=1.5,
      limitOn=1, limitThresh=0.98, limitDur=0.01|
      var env1, env2, o1,o2,o3,o4,o5,o6, s, a, b, sum;
      env1 = Env.perc(0.1, decay, curve:-3).ar(doneAction:2);
      env2 = Env([0,1,0], [0, decay*5], -150).ar;
      o1 = LFPulse.ar(tone + 3.52);   o2 = LFPulse.ar(tone + 166.31);
      o3 = LFPulse.ar(tone + 101.77); o4 = LFPulse.ar(tone + 318.19);
      o5 = LFPulse.ar(tone + 611.16); o6 = LFPulse.ar(tone + 338.75);
      s  = o1+o2+o3+o4+o5+o6;
      s  = BHiShelf.ar(BHiPass4.ar(BPeakEQ.ar(BPF.ar(BLowShelf.ar(s, 990, 2, -3), 7700), 7200, 0.5, 5), 8100, 0.7), 9400, 1, 5);
      a  = s * env1 * 0.6; b = s * env2;
      sum = LPF.ar(a + b, 4000) * level * 2;
      sum = Select.ar((limitOn > 0), [sum, Limiter.ar(sum, limitThresh, limitDur)]);
      Out.ar(out, Pan2.ar(sum, 0));
    }).add;

    // --- CLAP
    SynthDef(\dromedaryClap2, { |out=0, level=0.4,
      limitOn=1, limitThresh=0.98, limitDur=0.01|
      var atkenv, denv, atk, dec, sig;
      atkenv = Env([0.5,1,0],[0,0.3], -160).ar(doneAction:2);
      denv   = Env.dadsr(0.016,0,6,0,1,1,-157).ar;
      atk = WhiteNoise.ar * atkenv * 2;
      dec = WhiteNoise.ar * denv;
      sig = HPF.ar(BPF.ar((atk + dec * level), 1062, 0.5), 500) * 1.5;
      sig = Select.ar((limitOn > 0), [sig, Limiter.ar(sig, limitThresh, limitDur)]);
      Out.ar(out, Pan2.ar(sig, 0));
    }).add;

    // --- RIMSHOT
    SynthDef(\dromedaryRim2, { |out=0, level=1.0,
      limitOn=1, limitThresh=0.98, limitDur=0.01|
      var env, tri1, tri2, punch, sig;
      env  = Env([1,1,0], [0.00272, 0.07], -42).ar(doneAction:2);
      tri1 = LFTri.ar(1667 * 1.1, 1) * env;
      tri2 = LFPulse.ar(455  * 1.1, width:0.8) * env;
      punch= WhiteNoise.ar * env * 0.46;
      sig  = HPF.ar(LPF.ar(BPeakEQ.ar(tri1 + tri2 + punch, 464, 0.44, 8), 7300), 315) * level;
      sig  = Select.ar((limitOn > 0), [sig, Limiter.ar(sig, limitThresh, limitDur)]);
      Out.ar(out, Pan2.ar(sig, 0));
    }).add;

    // --- COWBELL
    SynthDef(\dromedaryCow2, { |out=0, level=0.3,
      limitOn=1, limitThresh=0.98, limitDur=0.01|
      var atkenv, env, pul1, pul2, atk, body, sig;
      atkenv = Env.perc(0, 1, 0.1, -215).ar(doneAction:2);
      env    = Env.perc(0.01, 9.5, 0.7, -90).ar;
      pul1   = LFPulse.ar(811.16);
      pul2   = LFPulse.ar(538.75);
      atk    = (pul1 + pul2) * atkenv * 6;
      body   = (pul1 + pul2) * env;
      sig    = HPF.ar(LPF.ar((atk + body) * level, 3500), 250);
      sig    = Select.ar((limitOn > 0), [sig, Limiter.ar(sig, limitThresh, limitDur)]);
      Out.ar(out, Pan2.ar(sig, 0));
    }).add;

    // --- CLAVES
    SynthDef(\dromedaryClv2, { |out=0, level=0.2,
      limitOn=1, limitThresh=0.98, limitDur=0.01|
      var env, sig;
      env = Env([1,1,0], [0, 0.1], -20).ar(doneAction:2);
      sig = SinOsc.ar(2500, pi/2) * env * level;
      sig = Select.ar((limitOn > 0), [sig, Limiter.ar(sig, limitThresh, limitDur)]);
      Out.ar(out, Pan2.ar(sig, 0));
    }).add;

    // --- MID TOM
    SynthDef(\dromedaryTom2, { |out=0, level=1.0, tone=120, decay=0.4,
      limitOn=1, limitThresh=0.98, limitDur=0.01|
      var env, fenv, sig;
      env  = Env([0.4,1,0],[0, decay, -250]).ar(doneAction:2);
      fenv = Env([tone*1.3333, tone*1.125, tone],[0.1, 0.5], -4).kr;
      sig  = SinOsc.ar(fenv, pi/2) * env * level * 2;
      sig  = Select.ar((limitOn > 0), [sig, Limiter.ar(sig, limitThresh, limitDur)]);
      Out.ar(out, Pan2.ar(sig, 0));
    }).add;

    // ------------------------------------------------------------------------
    // COMMANDS (robust): named OSC commands exposed to norns Lua
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

    // noteOn: start/replace a voice at a specific id; ensures no stacks
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
        old.free;
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

    // free a contiguous id range [lo..hi] (hard)
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

    // Live mixing: setLevelRange / setLevelId (post-chain level preferred)
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

    // PAN control
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

    // Global limiter controls
    this.addCommand("limitOn", "i", { |...args|
      limitOn = lastInt.(args, limitOn).clip(0, 1);
      voices.do { |assoc| var s = assoc.value; if(s.notNil) { s.set(\limitOn, limitOn) } };
    });

    this.addCommand("limitThresh", "f", { |...args|
      limitThresh = lastNumber.(args, limitThresh).clip(0.5, 2.0);
      voices.do { |assoc| var s = assoc.value; if(s.notNil) { s.set(\limitThresh, limitThresh) } };
    });

    this.addCommand("limitDur", "f", { |...args|
      limitDur = lastNumber.(args, limitDur).clip(0.0, 0.2);
      voices.do { |assoc| var s = assoc.value; if(s.notNil) { s.set(\limitDur, limitDur) } };
    });

    // ------------------------------------------------------------------------
    // Drum triggers (robust arg parsing like kick)
    // ------------------------------------------------------------------------
    this.addCommand("kick", "fff", { |q|
      var nums, a, t, d;
      nums = getNums.(q);
      a = (nums.size >= 3).if({ nums.at(nums.size-3).asFloat }, { 0.9 });
      t = (nums.size >= 3).if({ nums.at(nums.size-2).asFloat }, { 48.0 });
      d = (nums.size >= 3).if({ nums.at(nums.size-1).asFloat }, { 0.60 });
      Synth.tail(group, \dromedaryKick2, [\amp, a, \tune, t, \decay, d,
        \limitOn, limitOn, \limitThresh, limitThresh, \limitDur, limitDur]);
    });

    this.addCommand("snare", "fff", { |q|
      var nums, a, t, d;
      nums = getNums.(q);
      a = (nums.size >= 3).if({ nums.at(nums.size-3).asFloat }, { 0.8 });
      t = (nums.size >= 3).if({ nums.at(nums.size-2).asFloat }, { 340.0 });
      d = (nums.size >= 3).if({ nums.at(nums.size-1).asFloat }, { 3.2 });
      Synth.tail(group, \dromedarySnare2, [\level, a, \tone, t, \decay, d,
        \limitOn, limitOn, \limitThresh, limitThresh, \limitDur, limitDur]);
    });

    this.addCommand("ch", "fff", { |q|
      var nums, a, t, d;
      nums = getNums.(q);
      a = (nums.size >= 3).if({ nums.at(nums.size-3).asFloat }, { 0.9 });
      t = (nums.size >= 3).if({ nums.at(nums.size-2).asFloat }, { 500.0 });
      d = (nums.size >= 3).if({ nums.at(nums.size-1).asFloat }, { 1.5 });
      Synth.tail(group, \dromedaryCH2, [\level, a, \tone, t, \decay, d,
        \limitOn, limitOn, \limitThresh, limitThresh, \limitDur, limitDur]);
    });

    this.addCommand("oh", "fff", { |q|
      var nums, a, t, d;
      nums = getNums.(q);
      a = (nums.size >= 3).if({ nums.at(nums.size-3).asFloat }, { 0.9 });
      t = (nums.size >= 3).if({ nums.at(nums.size-2).asFloat }, { 400.0 });
      d = (nums.size >= 3).if({ nums.at(nums.size-1).asFloat }, { 1.5 });
      Synth.tail(group, \dromedaryOH2, [\level, a, \tone, t, \decay, d,
        \limitOn, limitOn, \limitThresh, limitThresh, \limitDur, limitDur]);
    });

    this.addCommand("clap", "f", { |q|
      var a;
      a = lastNumber.(q, 0.4).clip(0, 1.5);
      Synth.tail(group, \dromedaryClap2, [\level, a,
        \limitOn, limitOn, \limitThresh, limitThresh, \limitDur, limitDur]);
    });

    this.addCommand("rimshot", "f", { |q|
      var a;
      a = lastNumber.(q, 1.0).clip(0, 1.5);
      Synth.tail(group, \dromedaryRim2, [\level, a,
        \limitOn, limitOn, \limitThresh, limitThresh, \limitDur, limitDur]);
    });

    this.addCommand("cowbell", "f", { |q|
      var a;
      a = lastNumber.(q, 0.3).clip(0, 1.5);
      Synth.tail(group, \dromedaryCow2, [\level, a,
        \limitOn, limitOn, \limitThresh, limitThresh, \limitDur, limitDur]);
    });

    this.addCommand("claves", "f", { |q|
      var a;
      a = lastNumber.(q, 0.2).clip(0, 1.5);
      Synth.tail(group, \dromedaryClv2, [\level, a,
        \limitOn, limitOn, \limitThresh, limitThresh, \limitDur, limitDur]);
    });

    this.addCommand("mt", "fff", { |q|
      var nums, a, t, d;
      nums = getNums.(q);
      a = (nums.size >= 3).if({ nums.at(nums.size-3).asFloat }, { 1.0 });
      t = (nums.size >= 3).if({ nums.at(nums.size-2).asFloat }, { 120.0 });
      d = (nums.size >= 3).if({ nums.at(nums.size-1).asFloat }, { 0.4 });
      Synth.tail(group, \dromedaryTom2, [\level, a, \tone, t, \decay, d,
        \limitOn, limitOn, \limitThresh, limitThresh, \limitDur, limitDur]);
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
