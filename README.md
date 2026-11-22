# ofmana

Application web de gestion d'agence : fiches modèles, revenus, planning de contenu et tâches.

Tout tient dans un seul fichier, `index.html`, sans dépendance ni étape de build. Il suffit de l'ouvrir dans un navigateur.

## Fonctionnalités

- **Tableau de bord** : CA du mois, part agence, abonnés, tâches en retard, revenus sur 6 mois par modèle, classement.
- **Modèles** : fiches à onglets (profil, revenus, réseaux et notes), statut en un clic, commission au curseur avec calcul en direct.
- **Prospection** : tableau en glisser-déposer des @ Instagram, de « À contacter » jusqu'à « Signée » (fiche modèle créée automatiquement, vérification de la majorité obligatoire).
- **Statistiques** : CA par mois (3, 6 ou 12 mois), CA brut vs part agence, répartition par modèle, entonnoir de recrutement, production, tableau de performance triable. Infobulles au survol.
- **Planning** : contenus des 14 prochains jours (post, PPV, story, live, promo) avec leur statut.
- **Tâches** : priorités, échéances, responsables, filtre des tâches en retard.
- **Réglages** : export et import d'une sauvegarde en JSON.

## Données

L'application démarre vide. Hors de claude.ai, elles sont enregistrées dans le `localStorage` du navigateur.

Ce repo étant public, n'y versionnez jamais de vraies données de modèles.
