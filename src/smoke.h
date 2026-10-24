#pragma once
#include <QStringList>
class Backend;
class QQmlApplicationEngine;
// Explicit diagnostic mode; never reads or writes the user's shortcut profile.
void startSmokeTest(Backend &backend, QQmlApplicationEngine &engine, const QStringList &args);
