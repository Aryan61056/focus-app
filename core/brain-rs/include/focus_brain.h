#ifndef FOCUS_BRAIN_H
#define FOCUS_BRAIN_H
// C ABI of the focus brain (core/brain-rs/src/ffi.rs). JSON in, JSON out.
typedef struct FocusBrain FocusBrain;
FocusBrain *focus_brain_new(void);
void focus_brain_free(FocusBrain *brain);
// event_json: one event in the golden-trace shape. Returns a JSON array of effects, or NULL if the event could not be read.
char *focus_brain_step(FocusBrain *brain, double t, const char *event_json);
void focus_brain_free_string(char *s);
#endif
