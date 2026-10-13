# Licences tierces

Bouncer redistribue les travaux ci-dessous. Leurs auteurs en gardent le droit d'auteur, et les
termes qui suivent s'appliquent à ces parties du code, pas au reste du dépôt.

---

## AppleHello — tracé du mot « hello »

Le chemin de Bézier de `TraceHello` (`Sources/Bouncer/FenetreAccueil.swift`) vient de
[mtynior/AppleHello](https://github.com/mtynior/AppleHello). Les 21 courbes sont reprises telles
quelles, transposées du repère normalisé 0…1 vers un repère 0…1000.

```
MIT License

Copyright (c) 2023 Michal Tynior

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR OTHER DEALINGS IN THE SOFTWARE.
```

Une réserve : le tracé reproduit un lettrage manuscrit dessiné par Apple. La licence MIT couvre
le travail de vectorisation de Michal Tynior, pas les droits d'Apple sur le lettrage d'origine.
Bouncer n'est ni affilié à Apple ni approuvé par Apple. Si Apple demande le retrait du lettrage,
il faut le remplacer.


---

## sentry-cocoa — rapports de plantage (optionnels)

[getsentry/sentry-cocoa](https://github.com/getsentry/sentry-cocoa), version 9.28.0, liée dans le binaire.
Elle ne démarre que si l'utilisateur coche « Envoyer les rapports de plantage » (voir `docs/CONFIDENTIALITE.md`).

```
The MIT License (MIT)

Copyright (c) 2015 Sentry

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## KSCrash — capture des plantages

[kstenerud/KSCrash](https://github.com/kstenerud/KSCrash), version 2.6.0, dépendance de sentry-cocoa, liée dans le binaire.

```
MIT License

Copyright (c) 2012 Karl Stenerud

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
