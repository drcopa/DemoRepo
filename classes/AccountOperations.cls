public class AccountOperations {
    public static Account setDefaultDescription(Account a) {
        a.Description = '{!Environment.defaultDescription}';
        return a;
    }
}