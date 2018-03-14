// 
// TestWrapperExampleController()
//
@isTest
private class TestWrapperExampleController {
    public static testMethod void testController() {
        // create an account so that there is at least one available
        Account acc1=new Account(Name='Unit Test 1', 
                                 BillingStreet='East Village',
                                 BillingCity='New York City',
                                 BillingPostalCode='10009');
        insert acc1;
        
        // instantiate the controller
        WrapperExampleController ctrl=new WrapperExampleController();
        
        // check that there is at least one account
        Integer accSize=ctrl.getAccounts().size();
        System.assert(accSize>=1);
        
        List<WrapperExampleController.RowWrapper> rows = ctrl.getRowWrappers();
		System.assertEquals(4, rows.size());
		
        System.assertEquals(accSize, rows[0].values.size());
        
        // the number of column headings should be the same as the number of accounts
        System.assertEquals(accSize, ctrl.getHeadWrap().values.size());
    }
}