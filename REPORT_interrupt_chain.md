# Doubao DEX — ConversationInterruptProcessor V3 chain (classes24.dex)

All line numbers are dump lines in `D:\aiwork\apk\d24.txt` (the `classes24.dex` dexdump).
All offsets are the `|xxxx:` code-unit offsets printed inside the method body.

## 0. Absolute answer first

`lastSendSuccessMsgId` and `lastSendLocalMsgId` are **not stored fields read from disk**.
They are recomputed on every stop tap inside `com.larus.im.internal.core.conversation.group.d.process()`
(obfuscated `ConversationInterruptProcessorV3`) from the newest assistant `MessageEntity`:

* `lastSendSuccessMsgId` = `v6` in `process()` — the same register the app itself logs as
  `"lastSendSuccessMsgId: "` (d24.txt:191502/191504) and as `"breakSendId = "`
  (d24.txt:191440/191442). It comes from `MessageEntity.getMessageId()` / `getReplyId()`
  (d24.txt:191096/191098/191233).
* `lastSendLocalMsgId` = `v9` = `MessageEntity.getLocalMessageId()` at offset `0300`
  (d24.txt:191312 → `0303: move-result-object v9`).

They are captured by `ConversationInterruptProcessorV3$interruptLocal$1` and handed to JNI
`OmniMessageService.interruptMessage` as the 3rd/4th String params.

---

## 1. Every construction of `ConversationInterruptProcessorV3` (not `$...`)

**There is no class descriptor `Lcom/larus/im/internal/core/conversation/group/ConversationInterruptProcessorV3;`
anywhere in this dex.** A literal full-file scan returns `TOTAL HITS: 0`. The name survives only
inside the printed descriptors of its inner classes.

Evidence of the real (obfuscated) class:

* `ConversationInterruptProcessorV3$interruptLocal$1.this$0` is typed
  `'Lcom/larus/im/internal/core/conversation/group/d;'` — d24.txt:178971-178972, field@086b.
* `ConversationInterruptProcessorV3$interruptLocal$1$a.this$0` is typed
  `'Lcom/larus/im/internal/core/conversation/group/d;'` — d24.txt:178371, field@085e.

So the real class is `com.larus.im.internal.core.conversation.group.d`
(class descriptor at d24.txt:190768, `PUBLIC FINAL`, super `Lcom/larus/im/internal/core/IMActionProcessor;`).

Its ctor (d24.txt:190832, method@1512, body offset `48c80`):

```
190831  type: (Ljava/lang/String;ILjava/util/List;ZZLcom/larus/im/internal/jni/bean/OmniBreakReason;Lcom/larus/im/callback/IIMCallback;)V
190833  const-string v2, "conversationId"
190835  const-string v2, "breakReason"
190844  const-string v2, "ConversationInterruptV3"   // -> iput field@08d5 (g)
```

**The only `new-instance` of `group/d` in the whole dex** is inside
`ConversationServiceImpl.tryInterrupt` (impl at d24.txt:137742, body offset `46fed0`, 644 insns, 22 regs):

```
138041  47038c: new-instance v8, Lcom/larus/im/internal/core/conversation/group/d;
138050  4703ac: invoke-direct ... group/d;.<init>
138051  4703b2: invoke-virtual {v8}, ...group/d;.run:()V
```

Sibling (non-V3) `group/b`, same method, same args:

```
138053  4703ba: new-instance v8, Lcom/larus/im/internal/core/conversation/group/b;
138062  4703da: invoke-direct ... group/b;.<init>
138063  4703e0: invoke-virtual {v8}, ...group/b;.run:()V
```

Branch selector (which of `d`/`b` is built):

```
137797  46ffc6: sget v0, Lcom/larus/im/internal/core/conversation/group/d;.h:I      field@08c9
137801  46ffd4: invoke-static {}, Lcom/larus/im/internal/delegate/y0;.d:()Lcom/larus/im/internal/delegate/y0$k;
137803  46ffdc: iget-boolean v2, v2, Lcom/larus/im/internal/delegate/y0$k;.a:Z
137804  46ffe0: const-string v0, "ConversationInterruptV3"
137806  46ffe8: if-eqz v2, 0162
```

Ctor args (both classes): `v1=v15`(conversationId), `v2=v16`(int conversationType), `v3=v17`(List),
`v4=v18`(boolean), `v5=v19`(boolean), `v6=v20`(OmniBreakReason), `v7=v21`(IIMCallback).

### Public entry

`Lcom/larus/im/service/r;.tryInterrupt` — declared `PUBLIC ABSTRACT` at d24.txt:136785-136786 (#31):

```
(Ljava/lang/String;ILjava/util/List;ZZLcom/larus/im/internal/jni/bean/OmniBreakReason;Lcom/larus/im/callback/IIMCallback;)V
```

`ConversationServiceImpl` implements it (d24.txt:137742). **Sole dex call site** (grep TOTAL HITS: 1):
`NativeConversationServiceImpl.tryInterrupt` at d24.txt:1214523 (offset `5d644c`), forwarding at

```
1214537  5d6486: invoke-interface/range {v1..v8}, Lcom/larus/im/service/r;.tryInterrupt:(...)V   // method@bd04
```

Arg semantics from the log strings inside `tryInterrupt`:
`", conversationType:"` (`46ff12`), `", inputIds:"` (`46ff26`), `"lastSendMsg:"` (`47009e`),
`",answerIds:"` (`4700c6`), `"lastSendMsg is null,inputMsgList:"` (`4702e4`),
`"newestMessage is null,inputMsgList:"` (`47020a`). It builds
`List<Pair<getMessageId(), getLocalMessageId()>>` from each `Message` (`46ff74`/`46ff7c`),
so the `List` arg is `List<com.larus.im.bean.message.Message>`.

---

## 2. Backward trace of the ctor String params

`group/d.process:()V` — `PUBLIC FINAL`, header d24.txt:190911, body offset `480ce4`,
regs 17, ins 1, outs 7, insns size 1246.

### 2.1 The lambda that carries the ids

Ctor of `ConversationInterruptProcessorV3$interruptLocal$1`
(d24.txt:178976-178977, method@14aa, body offset `47d1bc`, d24.txt:178984-178992):

```
178984  47d1bc: ...$interruptLocal$1.<init>:(Ljava/util/List;Lcom/larus/im/internal/core/conversation/group/d;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Lkotlin/coroutines/Continuation;)V
178985  47d1cc: iput-object v1, v0, ...$interruptLocal$1;.$answerList:Ljava/util/List;            field@0865
178986  47d1d0: iput-object v2, v0, ...$interruptLocal$1;.this$0:Lcom/.../group/d;               field@086b
178987  47d1d4: iput-object v3, v0, ...$interruptLocal$1;.$replyFor:Ljava/lang/String;            field@0868
178988  47d1d8: iput-object v4, v0, ...$interruptLocal$1;.$lastSendSuccessMsgId:Ljava/lang/String; field@0867
178989  47d1dc: iput-object v5, v0, ...$interruptLocal$1;.$lastSendLocalMsgId:Ljava/lang/String;   field@0866
```

Call site inside `d.process` (d24.txt:191517-191525):

```
191517  049b: new-instance v13, ...ConversationInterruptProcessorV3$interruptLocal$1;
191519  049e: move-object v0, v13
191520  049f: move-object/from16 v2, v16          // this$0 = group/d
191521  04a1: move-object v3, v6                  // $replyFor
191522  04a2: move-object v4, v6                  // $lastSendSuccessMsgId
191523  04a3: move-object v5, v9                  // $lastSendLocalMsgId
191524  04a4: move-object v6, v8                  // (const/4 v8,#0 at 049d) continuation slot
191525  04a5: invoke-direct/range {v0,v1,v2,v3,v4,v5,v6}, ...$interruptLocal$1;.<init>:(...)V // method@14aa
```

**⇒ `$replyFor = v6`, `$lastSendSuccessMsgId = v6`, `$lastSendLocalMsgId = v9`.**

### 2.2 Where v9 comes from (lastSendLocalMsgId) — fully resolved

```
191311  02ff: move-object v6, v3
191312  0300: invoke-virtual {v10}, Lcom/larus/im/internal/database/entity/MessageEntity;.getLocalMessageId:()Ljava/lang/String;  // method@204c
191313  0303: move-result-object v9
```

`v10` is a `MessageEntity` (`check-cast v10, ...MessageEntity;` at d24.txt:191117 `017f`).
`v9` is written nowhere else between `0303` and the lambda construction at `04a3`, and the
write trace confirms `v9 → 0495` is untouched: the only later v9 writers are
`03b...`? none — `0303` is the last `move-result-object v9` before `04a3`.

### 2.3 Where v6 comes from (lastSendSuccessMsgId / replyFor)

The app labels this register itself:

```
191502  0479: const-string v4, "lastSendSuccessMsgId: "        // string@a2a6
191504  047e: invoke-virtual {v3, v6}, Ljava/lang/StringBuilder;.append:(Ljava/lang/String;)...   // v6 appended
...
191440  03ee: const-string v4, "breakSendId = "               // string@78e1
191442  03f3: invoke-virtual {v3, v6}, Ljava/lang/StringBuilder;.append:(Ljava/lang/String;)...
```

Its DB origin is the same `MessageEntity` id family:

```
191233  0261: invoke-virtual {v10}, ...MessageEntity;.getMessageId:()Ljava/lang/String;   // method@204e  -> v1
191096  0159: invoke-virtual {v3}, ...MessageEntity;.getMessageId:()Ljava/lang/String;    // method@204e
191098  015e: invoke-virtual {v3}, ...MessageEntity;.getReplyId:()Ljava/lang/String;      // method@2057
191095  0157: if-ne v9, v6, 015e      // v6 == 1 here (const/4 v6,#1 at 0104) => getUserType() branch
```

`v6` is also consumed as the "replyFor" side-table key:

```
191435  03e4: invoke-static {v3}, Lcom/larus/im/internal/core/message/utils/f;.b:(Ljava/lang/String;)V  // method@1979
```

which is `MessageInterruptHelper.b(replyFor)` (see §5 / d24.txt:321531+).

> **FLAGGED / UNDETERMINED:** the exact branch polarity of the null-check at
> `191078 0138: if-nez v3, 0153 // +001b` could not be reduced to a single CFG from the
> linear dexdump alone (`flow.ps1` is a linear register trace, not a CFG). What is certain:
> the value is a `MessageEntity` message/reply id chosen by `getUserType()`
> (offsets `0153`–`0161`, d24.txt:191093-191100), the code's own log calls it
> `lastSendSuccessMsgId`, and it is the same value passed as `$replyFor`.

### 2.4 Consumption — `group/f.invoke` performs the JNI call

`group/f` fields (`a:group/d`, `b:String`, `c:String`, `d:Map`, `e:group/e`, `f:List`);
`group/f.<init>:(Lcom/.../group/d;Ljava/lang/String;Ljava/lang/String;Ljava/util/Map;Lcom/.../group/e;Ljava/util/List;)V`
method@1517, constructed at d24.txt:179163 (`47d3dc`).

Body `group/f.invoke:(Ljava/lang/Object;)Ljava/lang/Object;` — d24.txt:192947 (`481734`), regs 12:

```
192948  0000: iget-object v0, v10, ...group/f;.a:Lcom/.../group/d;            field@08d8
192949  0002: iget-object v4, v10, ...group/f;.b:Ljava/lang/String;           field@08d9   (= lastSendSuccessMsgId)
192950  0004: iget-object v5, v10, ...group/f;.c:Ljava/lang/String;           field@08da   (= lastSendLocalMsgId)
192951  0006: iget-object v6, v10, ...group/f;.d:Ljava/util/Map;              field@08db   (= modifyAnswerMap)
192952  0008: iget-object v1, v10, ...group/f;.e:Lkotlin/jvm/functions/Function0;
192953  000a: iget-object v2, v10, ...group/f;.f:Ljava/util/List;
192954  000c: check-cast v11, Lcom/larus/im/internal/jni/service/OmniMessageService;
192955  000e: iget-boolean v3, v0, ...group/d;.d:Z                            field@08d2
192956  0010: iget-object v7, v0, ...group/d;.a:Ljava/lang/String;            field@08cf   (= conversationId)
192957  0012: iget-object v8, v0, ...group/d;.f:Lcom/.../OmniBreakReason;     field@08d4
192958  0014: new-instance v9, ...ConversationInterruptProcessorV3$interruptLocal$1$a;
192959  0016: invoke-direct {v9, v0, v1, v2}, ...$a;.<init>:(Lcom/.../group/d;Lkotlin/jvm/functions/Function0;Ljava/util/List;)V  // method@14a1
192965  001e: invoke-virtual/range {v1,v2,v3,v4,v5,v6,v7,v8}, Lcom/larus/im/internal/jni/service/OmniMessageService;.interruptMessage:(ZLjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/util/Map;Lcom/larus/im/internal/jni/bean/OmniBreakReason;Lcom/larus/im/internal/jni/callback/OmniIMCallback;)V  // method@5e2a
```

JNI param order confirmed:
`(Z interruptServer, String conversationId, String lastSendMsgId, String lastSendMsgLocalId, Map modifyAnswerMap, OmniBreakReason, OmniIMCallback)`
⇒ **`f.b` = 3rd String = lastSendSuccessMsgId; `f.c` = 4th String = lastSendLocalMsgId.**

Where `f.b`/`f.c` are filled (d24.txt:179159-179160, inside `interruptLocal$1.invokeSuspend`):

```
179158  00a5: iget-object v3, v9, ...$interruptLocal$1;.this$0:Lcom/.../group/d;                  field@086b
179159  00a7: iget-object v4, v9, ...$interruptLocal$1;.$lastSendSuccessMsgId:Ljava/lang/String;  field@0867
179160  00a9: iget-object v5, v9, ...$interruptLocal$1;.$lastSendLocalMsgId:Ljava/lang/String;    field@0866
179161  00ab: new-instance v0, ...group/f;
179163  00ae: invoke-direct/range {v2,v3,v4,v5,v6,v7,v8}, ...group/f;.<init>:(...)V              // method@1517
179164  00b1: invoke-virtual {v10, v0}, Lcom/larus/im/internal/jni/OmniIMSDK;.withMessageService:(Lkotlin/jvm/functions/Function1;)V  // method@275a
```

### 2.5 Where the Map (modifyAnswerMap) comes from

`interruptLocal$1.invokeSuspend` (d24.txt:179126-179139):

```
179126  47d35e: iget-object v10, v9, ...$interruptLocal$1;.this$0:Lcom/.../group/d;   field@086b
179127  47d362: iget-object v4, v10, ...group/d;.a:Ljava/lang/String;                  field@08cf
179128  47d366: const-string v5, ""             // string@0000  (threadId)
179129  47d36a: iget-object v6, v9, ...$interruptLocal$1;.$answerList:Ljava/util/List; field@0865
179130  47d36e: iget-object v7, v9, ...$interruptLocal$1;.$replyFor:Ljava/lang/String; field@0868
179134  47d37c: invoke-virtual/range {v3,v4,v5,v6,v7,v8}, Lcom/larus/im/internal/core/message/MessageHandler;.o:(Ljava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;  // method@173c
179139  47d38c: check-cast v10, Ljava/util/Map;
179148  47d3a6: invoke-direct {v7, v6}, ...group/e;.<init>:(Ljava/util/Map;)V          // method@1515
```

`group/e` = `(Ljava/util/Map;)V` wrapper; `group/e.invoke` at d24.txt:192844 (`4816cc`) → if map
non-empty, `new-instance ...ConversationInterruptProcessorV3$interruptLocal$1$cancelTypewriter$1$1;`
+ `com/larus/im/internal/database/utils/e;.c`.

### 2.6 `d.process` tail (the onSuccess branches)

```
191485  0454: if-eqz v5, 0473
191487  0458: iget-object v1, v7, ...group/d;.g:Ljava/lang/String;    field@08d5
191489  045c: const-string v3, "break answer Ready cid = "
191497  046f: invoke-virtual {v7, v0}, Lcom/larus/im/internal/core/IMActionProcessor;.onSuccess:(Ljava/lang/Object;)V   // Boolean.TRUE
191501  0477: new-instance v3, Ljava/lang/StringBuilder;
191503  0479: const-string v4, "lastSendSuccessMsgId: "
191507  0486: iget-object v4, v7, ...group/d;.a:Ljava/lang/String;     field@08cf
191512  0492: invoke-static {v6}, Lcom/larus/im/internal/core/message/utils/f;.b:(Ljava/lang/String;)V  // method@1979
191513  0495: invoke-virtual/range {v16}, Lcom/larus/im/internal/core/IMActionProcessor;.getScope:()Lkotlinx/coroutines/CoroutineScope;
191547  04b9: const-string v3, "last send msg id = "
191549  04da: invoke-virtual {v7, v0}, ...onSuccess
```

Other early-exit logs in `process`: `"process interruptV3 conversationId:"` (`000d`),
`",conversationType:"` (`0017`), `",serverInterrupt:"` (`0021`), `"local conversation"` (`0046`),
`"wcb_message_hidden"` (`011f`) / `"true"` (`0125`), `"interrupt failed"` (`0136`), `"list:"` (`0187`),
`"deep_search_card"` (`0216`), `"deep_research_phase"` (`0224`),
`"dora record card, don't interrupt"` (`0244`), `"skip interrupt for no-break: reason="` (`0290`),
`", replyId="` (`029a`), `", chatId="` (`02a2`), `"breakSendId = "` (`03ee`),
`", conversation id = "` (`03f6`), `", ans: "` (`0400`).

---

## 3. Sibling `ConversationInterruptProcessor` (non-V3)

Real class = `com.larus.im.internal.core.conversation.group.b`.
`ConversationInterruptProcessor$interruptLocal$1.this$0` / `$serverInterrupt$1.this$0` are
`'Lcom/.../group/b;'` (d24.txt:177364, 177891). Ctor = same 7-arg signature (method@150c).

`ConversationInterruptProcessor$interruptLocal$1` ctor —
`(Ljava/util/List;Lcom/.../group/b;Ljava/lang/String;Ljava/util/List;Lkotlin/coroutines/Continuation;)V`,
method@1497, offset `47c9c4`, d24.txt:177362-177369:

```
$answerList:Ljava/util/List;  field@084c
this$0:Lcom/.../group/b;      field@0856
$replyFor:Ljava/lang/String;  field@084e
$list:Ljava/util/List;        field@084d
```

**Only ONE String** — there is no separate local-id capture in the non-V3 processor.
`serverInterrupt$1` ctor = `(Ljava/util/List;...group/b;Ljava/lang/String;Lkotlin/coroutines/Continuation;)V`
method@149c, offset `47cc78`.

`group/b.process()` (d24.txt:188655/188680):

```
188653  06e0: new-instance v13, ...ConversationInterruptProcessor$serverInterrupt$1;
188655  06e3: invoke-direct {v13, v5, v7, v9, v3}, ...$serverInterrupt$1;.<init>:(Ljava/util/List;Lcom/.../group/b;Ljava/lang/String;Lkotlin/coroutines/Continuation;)V  // method@149c
188674  0701: new-instance v13, ...ConversationInterruptProcessor$interruptLocal$1;
188680  0709: invoke-direct/range {v1,v2,v3,v4,v5,v6}, ...$interruptLocal$1;.<init>:(Ljava/util/List;Lcom/.../group/b;Ljava/lang/String;Ljava/util/List;Lkotlin/coroutines/Continuation;)V  // method@1497
188686  0715: iget-object v3, v7, ...group/b;.g:Ljava/lang/String;   field@08ce
188688  0719: const-string v5, "lastSendSuccessMsgId: "
188693  0726: iget-object v5, v7, ...group/b;.a:Ljava/lang/String;   field@08c8
```

`group/b.interruptLocal$1.invokeSuspend` (d24.txt:177480-177528): iterates `$answerList` as
`MessageEntity`, takes `getMessageId()` (else `""`), logs
`"local interrupt, messageId = "` + `", replyFor = "`, filters on
`MessageEntity.getReplyId()` == replyFor, then calls

```
177523  47cb9c: invoke-virtual {v8, v1, v3, v6, v15}, Lcom/larus/im/internal/core/message/MessageHandler;.x:(Ljava/lang/String;Lcom/larus/im/internal/database/entity/MessageEntity;Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;  // method@1745
```

⇒ the non-V3 path interrupts via `MessageHandler.x` and never needs the local id.

---

## 4. `getLatestMessage` declarations, overloads, boolean meaning

### Declarations

| Owner | Signature | Where | Access |
|---|---|---|---|
| `com.larus.im.service.IMessageService` | — | not declared | — |
| `MessageServiceImpl` | `getLatestMessage:(Ljava/lang/String;ZLcom/larus/im/callback/IIMCallback;)V` | d24.txt:252450 | `0x0001 (PUBLIC)` |
| `MessageServiceImpl` | `getLastLocalMessage:(Ljava/lang/String;Lcom/larus/im/callback/IIMCallback;)V` | d24.txt:252433 | `0x0001 (PUBLIC)` |
| `OmniMessageService` | `getLatestMessage:(Lcom/.../OmniMessageLatestRequest;Lcom/.../OmniIMCallback;)V` | d24.txt:1196663 | `0x0111 (PUBLIC FINAL NATIVE)` |
| `OmniMessageService` | `getLastLocalMessage:(Lcom/.../OmniGetLastLocalMessageRequest;Lcom/.../OmniIMCallback;)V` | d24.txt:1196657 | `0x0111 (PUBLIC FINAL NATIVE)` |
| `MessageDao` | `getLastLocalMessage:(Ljava/lang/String;Z)Lcom/.../MessageEntity;` | d24.txt:332002 | `0x0401 (PUBLIC ABSTRACT)` |
| `MessageDao` | `getLastLocalMessageId:(Ljava/lang/String;Z)Ljava/lang/String;` | d24.txt:332008 | `PUBLIC ABSTRACT` |
| `NativeMessageDaoImpl` | same two | d24.txt:530216 / 530222 | `0x0101 (PUBLIC NATIVE)` |
| `ConversationEntity` | `getLatestMessageIndex:()Ljava/lang/Long;` | idx24.tsv | — |

### `MessageServiceImpl.getLatestMessage` is a NO-OP STUB

```
252458  494118: com.larus.im.internal.core.message.MessageServiceImpl.getLatestMessage:(Ljava/lang/String;ZLcom/larus/im/callback/IIMCallback;)V
252459  494128: 0000: const-string v2, "conversationId"
252460  49412c: 0002: invoke-static {v1, v2}, Lkotlin/jvm/internal/Intrinsics;.checkNotNullParameter:(Ljava/lang/Object;Ljava/lang/String;)V
252461  494132: 0005: const-string v1, "callback"
252462  494136: 0007: invoke-static {v3, v1}, ...checkNotNullParameter:(Ljava/lang/Object;Ljava/lang/String;)V
252463  49413c: 000a: return-void
```

11 code units, no work at all. (Its sibling `getMessageById` at d24.txt:252469-252482 is likewise a stub.)
⇒ **the real `getLatestMessage` is only the JNI `OmniMessageService.getLatestMessage`
with an `OmniMessageLatestRequest` bean.**

### Boolean parameter meaning = `onlyVisible`

`OmniMessageLatestRequest` fields (idx24.tsv): `conversationId:Ljava/lang/String;`, `onlyVisible:Z`.
Primary ctor `(Ljava/lang/String;Z)V`; synthetic default ctor d24.txt:997939-997946:

```
997940  0000: and-int/lit8 v4, v3, #int 1
997942  0004: const/4 v1, #int 0          // conversationId -> null
997943  0005: and-int/lit8 v3, v3, #int 2
997945  0009: const/4 v2, #int 0          // onlyVisible -> false
997946  000a: invoke-direct {v0, v1, v2}, ...OmniMessageLatestRequest;.<init>:(Ljava/lang/String;Z)V
```

`component2:()Z` (d24.txt:998140-998142) returns `.onlyVisible`.
⇒ the boolean on both `MessageServiceImpl.getLatestMessage(String,boolean,IIMCallback)` and the
JNI request is **`onlyVisible`** (fetch only visible / non-hidden messages).

### "Only the user's latest message" API

* `OmniGetLastSenderMessageRequest` exists with fields `conversationId:Ljava/lang/String;` and
  `senderId:Ljava/lang/String;` (idx24.tsv), i.e. the bean is designed for "last message from a
  given sender" (the user).
* But **no method anywhere takes it as a parameter.** The only occurrences in the dex are its own
  bean members and its serializer:
  `com.larus.im.internal.jni.bean.OmniGetLastSenderMessageRequest$$serializer.serialize:(Lndc/f;Lcom/.../OmniGetLastSenderMessageRequest;)V`
  at d24.txt:945189 (call at d24.txt:945241, offset `57c2cc`).
* ⇒ **UNDETERMINED**: there is no Java/Kotlin-visible "get the user's latest message" entry point in
  this dex. If it is used, it is consumed only from native code (the native service table also has no
  `getLastSenderMessage` method — full `OmniMessageService` method list was enumerated).

Nearest usable replacements for a module:
* `NativeMessageServiceImpl.l:(Ljava/lang/String;Lcom/larus/im/callback/IIMCallback;)V`
  (d24.txt:1220371, offset `5d8504`) → `"getLastLocalMessage"` (d24.txt:1220383) → `legacy/y2` →
  `OmniIMSDK.withMessageService` (d24.txt:1220395).
* `MessageDao.getLastLocalMessage(conversationId, onlyVisible)` /
  `getLastLocalMessageId(conversationId, onlyVisible)` (NATIVE impl at d24.txt:530216/530222).
* `MessageCache` (idx24.tsv) has `x(String,Z,Continuation)`, `c0(String,IZ,Continuation)`,
  `d0(String)`, `b0(String)`.

---

## 5. `MessageHandler.tryInterrupt` and `MessageHandler.o` (`MessageHandler.o:(String,String,List,String,Continuation)` @ `47d37c`)

Class `Lcom/larus/im/internal/core/message/MessageHandler;` at d24.txt:241206 (`PUBLIC FINAL`).
Public singleton: static field `a:Lcom/larus/im/internal/core/message/MessageHandler;`
(d24.txt:241211-241214), set in `<clinit>`:

```
241241  49093e: 0005: sput-object v0, Lcom/larus/im/internal/core/message/MessageHandler;.a:Lcom/larus/im/internal/core/message/MessageHandler;  // field@0aa8
```

Also static: `b:Lcom/larus/im/internal/core/message/concat/g;`, `c:Lcom/larus/im/internal/stream/StreamChannel;`, `d:Lkotlin/Lazy;`.

### 5.1 `o` = Kotlin `interruptTypewriter` (the method named in the `47d37c` call site)

```
246569  #3  (in Lcom/larus/im/internal/core/message/MessageHandler;)
246570  name   : 'o'
246571  type   : '(Ljava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;'
246572  access : 0x0011 (PUBLIC FINAL)
246574  registers : 24   ins : 6   outs : 4   insns size : 806 16-bit code units
246578  4921c8: |[4921c8] com.larus.im.internal.core.message.MessageHandler.o:(...)Ljava/lang/Object;
246579  0000: move-object/from16 v0, v23
246580  0002: instance-of v1, v0, Lcom/larus/im/internal/core/message/MessageHandler$interruptTypewriter$1;
246583  0007: check-cast v1, Lcom/larus/im/internal/core/message/MessageHandler$interruptTypewriter$1;
246584  0009: iget v2, v1, ...$interruptTypewriter$1;.label:I        field@0a29
```

The state-machine class name (`MessageHandler$interruptTypewriter$1`, d24.txt:230955) proves the
Kotlin name is `interruptTypewriter`.

**Parameter mapping** (from the two non-recursive callers):

* d24.txt:35641 (`4515ec`, bridge): `{MessageHandler.a, $cvsId, "", emptyList(), $questionId, cont}`
* d24.txt:179134 (`47d37c`, V3 processor): `{MessageHandler.a, d.a, "", $answerList, $replyFor, cont}`

⇒ `o(String cid, String threadId, List answerList, String replyFor, Continuation)`.
It returns the **`modifyAnswerMap`**: builds a `LinkedHashMap` at offset `0265`, iterates
`List<Message>` (`check-cast ..., Lcom/larus/im/bean/message/Message;`), and returns
`MapsKt.emptyMap()` early when `"trigger interruptTypewriter cid and threadId are empty"`.
Log strings inside: `" replyFor="`, `"trigger interruptTypewriter msgId="`,
`"trigger interruptTypewriter cid="`, `" threadId="`,
`"trigger interruptTypewriter cid and threadId are empty"`,
`"trigger interruptTypewriter replyFor="`, `" has input params is not full reply"`,
`" is serverLoading msg"`, `" is streaming msg"`; tag `"MessageHandler"` via
`Lcom/larus/im/internal/delegate/a;.i(String,String)`.

`o` callers (grep, 4 hits):
`35641` (bridge `interruptTypewriter`), `179134` (V3), `231045` (`48d58c`, own resumption
`MessageHandler$interruptTypewriter$1.invokeSuspend`), `1224613` (`5d9d98`,
`NativeThreadServiceImpl$interruptMessage$2.invokeSuspend`).

### 5.2 `tryInterrupt` — obfuscated as `w` and `x`

The Kotlin `tryInterrupt` compiles to **two** overloads (per-`Message` and per-`MessageEntity`):

```
249172  name : 'w'
249173  type : '(Ljava/lang/String;Lcom/larus/im/bean/message/Message;Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;'
249175  access : 0x0011 (PUBLIC FINAL)
249177  registers : 14  ins : 5  outs : 4  insns size : 338
249180  4930cc: |[4930cc] ...MessageHandler.w:(...)Ljava/lang/Object;
249181  0002: instance-of v1, v0, Lcom/larus/im/internal/core/message/MessageHandler$tryInterrupt$5;   // type@09b5
249193  493106: invoke-direct ...MessageHandler$tryInterrupt$5;.<init>  // method@171e
```

```
249704  name : 'x'
249705  type : '(Ljava/lang/String;Lcom/larus/im/internal/database/entity/MessageEntity;Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;'
249706  access : 0x0011 (PUBLIC FINAL)
249707  registers : 20  ins : 5
249711  0002: instance-of v1, v0, Lcom/larus/im/internal/core/message/MessageHandler$tryInterrupt$1;   // type@09b4
```

* `w` body touches `ChunkOperator.g(String,I)`, `UplinkMessageChannel.SSE`,
  `chunk/cache/a.c(String,channel)`, iterates an `Iterable`, logs `" replyFor="` with
  `StringBuilder.append(C 0x20)` and tag `"MessageHandler"`.
* `w` callers: d24.txt:240268 (`MessageHandler$tryInterrupt$5.invokeSuspend`) and
  **d24.txt:35405 (offset `4514dc`), `OmniNativeHandlerBridgeProvider$messageHandlerBridge$1$interruptOldSSE$1.invokeSuspend`**.
* `x` callers: d24.txt:240184 (`...$tryInterrupt$1.invokeSuspend`) and d24.txt:177523
  (`47cb9c`, `group/b`'s `interruptLocal$1`).

### 5.3 The runtime-critical non-suspend bridge

```
36498  #8  (in Lcom/larus/im/internal/OmniNativeHandlerBridgeProvider$messageHandlerBridge$1;)
36499  name   : 'interruptTypewriter'
36500  type   : '(Ljava/lang/String;Ljava/lang/String;)Ljava/util/Map;'
36501  access : 0x0011 (PUBLIC FINAL)
36503  registers : 5  ins : 3  outs : 4  insns size : 24
36507  4519e8: |[4519e8] ...$messageHandlerBridge$1.interruptTypewriter:(Ljava/lang/String;Ljava/lang/String;)Ljava/util/Map;
36508  0000: const-string v0, "cvsId"
36510  0005: const-string v0, "questionId"
36512  000a: new-instance v0, ...$messageHandlerBridge$1$interruptTypewriter$1;
36514  000d: invoke-direct {v0, v3, v4, v1}, ...$interruptTypewriter$1;.<init>:(Ljava/lang/String;Ljava/lang/String;Lkotlin/coroutines/Continuation;)V  // method@0e55
36516  0011: invoke-static {v1, v0, v3, v1}, Lkotlinx/coroutines/BuildersKt;.runBlocking$default:(...)                       // method@f021
36518  0015: check-cast v3, Ljava/util/Map;
36519  0017: return-object v3
```

Inner `invokeSuspend` (d24.txt:35632-35641):

```
35632  001a: sget-object v1, Lcom/larus/im/internal/core/message/MessageHandler;.a:Lcom/.../MessageHandler;  // field@0aa8
35633  001c: iget-object v8, v7, ...$interruptTypewriter$1;.$cvsId:Ljava/lang/String;      field@04a7
35634  001e: const-string v3, ""
35635  0020: invoke-static {}, Lkotlin/collections/CollectionsKt;.emptyList:()Ljava/util/List;
35637  0024: iget-object v5, v7, ...$interruptTypewriter$1;.$questionId:Ljava/lang/String; field@04a8
35641  002a: invoke-virtual/range {v1,v2,v3,v4,v5,v6}, Lcom/larus/im/internal/core/message/MessageHandler;.o:(...)Ljava/lang/Object;  // method@173c
```

⇒ **`interruptTypewriter(cvsId, questionId)` on the bridge returns the `modifyAnswerMap`
synchronously through `runBlocking` — no coroutine plumbing needed.**

Adapter on the JNI side:

```
540622  #8  (in Lcom/larus/im/internal/jni/adapter/NativeMessageHandlerAdapter;)
540623  name   : 'interruptTypewriter'
540624  type   : '(Ljava/lang/String;Ljava/lang/String;)Ljava/util/Map;'
540625  access : 0x0001 (PUBLIC)
540631  4f1d0c: |[4f1d0c] com.larus.im.internal.jni.adapter.NativeMessageHandlerAdapter.interruptTypewriter:(Ljava/lang/String;Ljava/lang/String;)Ljava/util/Map;
540636  000a: iget-object v0, v1, ...NativeMessageHandlerAdapter;.$$delegate_0:Lpb9/o;    field@1390
540637  000c: invoke-interface {v0, v2, v3}, Lpb9/o;.interruptTypewriter:(Ljava/lang/String;Ljava/lang/String;)Ljava/util/Map;  // method@f73c
```

### 5.4 Bridge wiring (how to reach it from Java)

```
36794  com.larus.im.internal.OmniNativeHandlerBridgeProvider
  b()Lpb9/o;  -> new-instance ...$messageHandlerBridge$1;   (451bb8, d24.txt:36882)

462390 Lcom/larus/im/internal/delegate/h1;        (PUBLIC FINAL, implements Lpb9/p;)
  static field b:Lcom/larus/im/internal/delegate/h1;
  instance field a:Lpb9/p;
462433 4d7b90: <init>:(...)V
462435 0003: invoke-static {}, Lab9/a;.a:()Lpb9/n;
462437 0007: invoke-interface {v0}, Lpb9/n;.a:()Lpb9/p;            // method@f731
462439 000b: iput-object v0, v1, Lcom/larus/im/internal/delegate/h1;.a:Lpb9/p;   field@1151
462470 4d7bbc: h1.a:()Lpb9/j; -> invoke-interface Lpb9/p;.a:()Lpb9/j;   // method@f742
462488 4d7bdc: h1.b:()Lpb9/o; -> invoke-interface Lpb9/p;.b:()Lpb9/o;   // method@f743
462497 4d7bf0: h1.c:()Lpb9/r; -> invoke-interface Lpb9/p;.c:()Lpb9/r;   // method@f744
```

⇒ from a module: `delegate.h1.b.a()` gives `Lpb9/j;` (conversation bridge),
`delegate.h1.b.b()` gives `Lpb9/o;` (message bridge, has `interruptTypewriter(String,String)Map`),
`delegate.h1.b.c()` gives `Lpb9/r;`.

---

## 6. Definitive runtime recipe (reachable by Java reflection / Xposed)

### 6.1 Read the two ids exactly as the real stop button produces them (recommended)

Hook the JNI method that receives them:

```
com.larus.im.internal.jni.service.OmniMessageService
  interruptMessage:(ZLjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/util/Map;
                    Lcom/larus/im/internal/jni/bean/OmniBreakReason;
                    Lcom/larus/im/internal/jni/callback/OmniIMCallback;)V
```

* call site: d24.txt:192965, offset `481780` (`invoke-virtual/range ... OmniMessageService;.interruptMessage`)
* `args[0]` = interruptServer  ← `group/d.d` (d24.txt:192955)
* `args[1]` = conversationId   ← `group/d.a` (d24.txt:192956)
* `args[2]` = **lastSendSuccessMsgId**
* `args[3]` = **lastSendLocalMsgId**
* `args[4]` = modifyAnswerMap  ← `MessageHandler.o` result (d24.txt:192951 / 179134)
* `args[5]` = OmniBreakReason  ← `group/d.f` (d24.txt:192957)

`interruptMessage` also has the `$default` companion
(`interruptMessage$default:(Lcom/larus/im/internal/jni/service/OmniMessageService;ZLjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/util/Map;Lcom/larus/im/internal/jni/bean/OmniBreakReason;Lcom/larus/im/internal/jni/callback/OmniIMCallback;ILjava/lang/Object;)V`).

Optional secondary hook (to observe the raw inputs, but the ids are NOT yet computed here):
`com.larus.im.internal.core.conversation.ConversationServiceImpl.tryInterrupt`
(d24.txt:137742) — `(String conversationId, int conversationType, List<Message> inputIds,
boolean serverInterrupt, boolean, OmniBreakReason, IIMCallback)`.

### 6.2 Trigger a stop programmatically

1. Get a live service. Sanctioned accessors: `com.larus.im.internal.jni.OmniSDKHelper.INSTANCE`
   → `getOmniSDK(String userId, boolean)` (or `getOmniSDK$default`) → `OmniIMSDK`
   → `withConversationService(Function1)` / `withMessageService(Function1)`
   (bodies at d24.txt:30076, 179164, 266038, 1216200, 1219001; `OmniIMSDK.withMessageService:(Lkotlin/jvm/functions/Function1;)V`
   method@275a). Inside the lambda you receive the native service instance
   (`check-cast v11, Lcom/larus/im/internal/jni/service/OmniMessageService;` d24.txt:192954).
2. Either
   * call `NativeConversationServiceImpl.tryInterrupt(conversationId, conversationType,
     listOf(Message beans), true, true, OmniBreakReason.OmniBreakReason_CLICK_BREAK_BUTTON, callback)`
     (d24.txt:1214523) which forwards to `Lcom/larus/im/service/r;.tryInterrupt` (d24.txt:1214537); or
   * call `ConversationServiceImpl.tryInterrupt(...)` directly. V3 is selected iff
     `com.larus.im.internal.delegate.y0;.d:()Lcom/.../y0$k;` has `.a == true`
     (d24.txt:137801-137806); otherwise `group/b` (non-V3) is used.
3. To obtain the `modifyAnswerMap` without replicating logic, call the bridge:
   `Lpb9/o;.interruptTypewriter(String cvsId, String questionId)` obtained from
   `com.larus.im.internal.delegate.h1.b.b()` (or from
   `NativeMessageHandlerAdapter.$$delegate_0`), or call
   `OmniNativeHandlerBridgeProvider$messageHandlerBridge$1.interruptTypewriter(String,String)`
   (d24.txt:36507) which uses `runBlocking` and returns the `Map` directly.
4. Feed that map into `OmniMessageService.interruptMessage(...)`, or let `tryInterrupt` do the whole thing.

### 6.3 Do NOT try to cache/reproduce the ids yourself

They are recomputed on every `group/d.process()` from the newest `MessageEntity`:
`getMessageId()`/`getReplyId()` (d24.txt:191096/191098/191233) and
`getLocalMessageId()` (d24.txt:191312, offset `0300`). There is no persisted
"lastSend..." field to read; the app's own log line `"lastSendSuccessMsgId: "`
(d24.txt:191502) prints exactly the register that is later passed as the JNI 3rd String param.

### 6.4 Interrupt-state side tables (useful when replicating)

`com.larus.im.internal.core.message.utils.f` — tag `"MessageInterruptHelper"` (d24.txt:321391):

```
static a:Ljava/lang/Object;   // lock                          field@0cd4
static b:Lus7/b;              // cancel/replyFor set           field@0cd5
static c:Lus7/b;              // ?                             field@0cd6
static d:Lus7/b;              // ?                             field@0cd7
```

* `b(String replyFor):V` — d24.txt:321531-321579: returns immediately if empty; returns unless
  `TextUtils.isDigitsOnly`; then synchronizes on `a`, `b.add(replyFor)`, and if `b.size() > 10`
  removes+logs the oldest (`"cancelSet add "` / `"cancelSet remove "`).
* `c(String replyFor, String chatId):Z` — d24.txt:321693-321708:
  `c.contains(replyFor) || CollectionsKt.contains(d, chatId)`.
* `a(String replyFor, String chatId):Z` — d24.txt:321482-321494:
  `c(replyFor, chatId) || !b.contains(replyFor)`.

`d.process` uses them at d24.txt:191253 (`0284: f.c(v3, v1)`) to bail out with
`"skip interrupt for no-break"`, and at d24.txt:191435 (`03e4: f.b(v6)`).

---

## 7. Undetermined / flagged items

1. **Branch polarity inside `d.process` offsets `0138`–`0161`.** The linear dexdump does not
   by itself prove which of `getMessageId()` / `getReplyId()` feeds `v6` on which path
   (`191078 0138: if-nez v3, 0153`); a real CFG would be needed. Certain: the value is a
   `MessageEntity` message/reply id selected via `getUserType()` (offsets `0153`–`0161`),
   it is what the code logs as `lastSendSuccessMsgId`, and it is passed as `$replyFor` too.
2. **"User's latest message" API.** `OmniGetLastSenderMessageRequest` (fields `conversationId`,
   `senderId`) has no consumer method in this dex — only its own bean/serializer members
   (d24.txt:945182/945189). No `getLastSenderMessage` exists on `OmniMessageService` at all
   (full native method list enumerated). If the feature is used, it is consumed only from native code.
3. **`ConversationInterruptProcessorV3` / `ConversationInterruptProcessor` class descriptors do not
   exist** in `classes24.dex`; all references in this report are to their obfuscated real classes
   `...group.d` and `...group.b`. There may be other copies in the other `classesN.dex` files of the APK
   (only `classes24.dex` was analysed here).
4. `f.c`'s two sets `c`/`d` are reachable only through the helper methods; their exact semantic
   labels (which one holds replyFor vs chatId) were inferred from the two argument positions
   (`replyFor`, `chatId`) and the `c(replyFor, chatId)` call at d24.txt:191253.
