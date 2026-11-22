# ofmana

Application web de gestion d'agence, avec deux espaces :

- **Admin (agence)** : fiches modèles, prospection en glisser-déposer, statistiques, planning de contenu, tâches.
- **Modèle** : chaque modèle se connecte et voit uniquement son planning, ses revenus, sa part et ses paiements, et les tâches que l'agence partage avec elle. Elle peut aussi envoyer ses photos et vidéos à l'agence.

Fonctions principales :
- **Import de relevés OnlyFans** (CSV), regroupés automatiquement par mois.
- **Paiements** : montant à verser, statut payé, relevé imprimable en PDF.
- **Contenus reçus** : envoi de photos et vidéos par les modèles, validation ou demande de retouche.
- **Calendrier** en glisser-déposer et export vers un agenda (.ics).
- **Rappels** : tâches, contenus, paiements, contrats, fuites et prospects à relancer.
- **Objectifs** mensuels, avec projection de fin de mois.
- **Onboarding** : checklist d'arrivée et coffre à documents privé.
- **Anti-fuite** : suivi des fuites et modèle de demande DMCA.
- **onlyAI**, l’agent IA (OpenAI, côté serveur) : il répond sur les données de l’agence et propose des actions (créer ou modifier des fiches, des tâches, des contenus, le CA, des paiements, des prospects…) que l’admin valide avant qu’elles s’appliquent. Il propose aussi des idées de contenus, des analyses et des messages de prospection.

Interface sombre, effet verre, accents violet et magenta. Le site tient dans un seul fichier, `index.html`, et ne demande aucune étape de build. Il est hébergé sur GitHub Pages, et les comptes et les données sont stockés sur Supabase.

**Mise en route : voir [SETUP.md](SETUP.md).**

## Fichiers

| Fichier | Rôle |
|---|---|
| `index.html` | L'application complète (interface, connexion, synchronisation) |
| `config.js` | Adresse et clé publique du projet Supabase |
| `supabase/setup.sql` | Tables, règles de sécurité (Row Level Security), stockage de fichiers et fonctions |
| `supabase/functions/assistant` | Fonction serveur de l'assistant IA (clé OpenAI en secret) |
| `SETUP.md` | Guide d'installation pas à pas |

## Sécurité

- Les droits d'accès sont appliqués par la base de données (Row Level Security), pas seulement par l'interface. Une modèle ne peut lire que sa fiche, ses contenus et les tâches marquées « Visible par elle ». Elle ne peut rien modifier, à part cocher ses tâches.
- Les notes de l'agence sur chaque modèle sont stockées dans une table séparée, réservée à l'admin.
- Le premier compte créé devient l'admin. Les comptes suivants sont des comptes modèles, reliés à leur fiche par leur email.
- Ce dépôt ne contient aucune donnée : tout est stocké dans Supabase.
