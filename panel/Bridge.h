#pragma once
// Registers a Darwin notification handler on the main queue (see notify(3)).
// Post with: notifyutil -p NAME
void rexmod_notify_register(const char *name, void (^handler)(void));
