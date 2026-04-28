/onChange(of: scenePhase)/,/^            }/!b
/onChange/c\
            .onChange(of: scenePhase) { _, phase in\
#if os(macOS)\
                if (phase == .background || phase == .inactive) && isUnlocked { lockApp() }\
                else if phase == .active { checkTimeLimit() }\
#else\
                if (phase == .background) && isUnlocked { lockApp() }\
                else if phase == .active { checkTimeLimit() }\
#endif\
            }
