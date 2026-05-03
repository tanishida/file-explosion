import plistlib

path = 'LimitBoxShare/Info.plist'
with open(path, 'rb') as f:
    plist = plistlib.load(f)

rule = plist['NSExtension']['NSExtensionAttributes']['NSExtensionActivationRule']
rule['NSExtensionActivationSupportsWebURLWithMaxCount'] = 10
rule['NSExtensionActivationSupportsWebPageWithMaxCount'] = 10
rule['NSExtensionActivationSupportsText'] = True

with open(path, 'wb') as f:
    plistlib.dump(plist, f)
